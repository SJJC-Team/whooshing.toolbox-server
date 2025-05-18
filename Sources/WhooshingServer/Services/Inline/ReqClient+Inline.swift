import Vapor
import ErrorHandle
import DataConvertable
import NIOCore
import Logging
import Cryptos
import WhooshingClient

/// 该文件实现了发送加密请求的功能。由于目标模块的加密算法并非传统的 HTTPS，
/// 而是自定的加密算法，因此向其请求时需要使用特定的加密逻辑。

public extension Inline {
    enum RequestErr: String, ErrList {
        public typealias ErrType = HTTPResponseError
        public var domain: String { "woo.sys.inline.reqclient.err" }
        case targetIncorrectResponseBody = "响应体解析失败"
        case unknowError = "响应不正确，未知错误"
    }
    
    enum RequestInternalErr: String, ErrList {
        public var domain: String { "woo.sys.inline.reqclient.internal.err" }
        case unknowSendError = "发送时遇到未知错误"
    }
}

final class InlineClient: ReqClient, WhooshingClient, StorageKey, @unchecked Sendable {
    typealias Value = InlineClient
    
    var key: Crypto.Symm.Key? {
        guard
            let ioData = self.storage[Inline.RequestIOData.self],
            let channel = self.channel,
            let key = ioData.connectionKeys[ObjectIdentifier(channel)]
        else { return nil }
        return key
    }
    
    @Sendable
    func send(
        _ method: HTTPMethod,
        headers: HTTPHeaders,
        to url: WebURI,
        bufferStrategy: BufferStrategy,
        beforeSend: @escaping BeforeSendAction,
        afterSend: @escaping AsyncAfterSendAction,
        progress: @escaping ProgressAction
    ) -> EventLoopFuture<HTTPResponse> {
        let req = HTTPRequest(method: method, url: url, headers: headers, body: nil)
        return self.makeChannel(url: req.url).flatMap { (channel, handler, _) in
            do {
                var request = req
                try beforeSend(&request, channel)
                request.channel = channel
                if case .collect = bufferStrategy {
                    self.logger?.info("Inline.Client-发送请求: \(channel.clientAddrInfo)")
                } else {
                    self.logger?.info("Inline.Client-发送流式请求: \(channel.clientAddrInfo)")
                }
                return self._send(request: request, bufferStrategy: bufferStrategy, channel: channel, handler: handler, progress: progress).flatMap { res in
                    afterSend(channel).map { res }
                }
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
    }
    
    deinit {
        Task { [weak self] in
            self?.logger?.debug("Inline.Client-主动关闭连接")
            await self?.closeAll()
        }
    }
}

extension InlineClient {
    private func _send(request: HTTPRequest, bufferStrategy: BufferStrategy, channel: Channel, handler: RequestHandler, progress: @escaping ProgressAction) -> EventLoopFuture<HTTPResponse> {
        let id = ObjectIdentifier(channel)
        let procedure: Int
        if self.requestIoData.connectionKeys[id] == nil { procedure = 0 }
        else if self.requestIoData.connectionValidate[id] != true { procedure = 1 }
        else { procedure = 2 }
        var r = channel.eventLoop.makeSucceededVoidFuture()
        switch (procedure) {
            case 0:
                r = r.flatMap {
                    self.logger?.debug("Inline.Client-与服务器首次请求，进行密钥交换: \(channel.clientAddrInfo)")
                    return self.keyExchange(req: request, channel: channel, handler: handler)
                }
                fallthrough
            case 1:
                r = r.flatMap {
                    self.logger?.debug("Inline.Client-与服务器配合进行服务验证: \(channel.clientAddrInfo)")
                    return self.serviceValidate(req: request, channel: channel, handler: handler)
                }
                fallthrough
            default:
                return r.flatMap {
                    self.logger?.debug("Inline.Client-与服务器发送真正请求: \(channel.clientAddrInfo)")
                    return self.send(request, channel: channel, handler: handler, bufferStrategy: bufferStrategy, progress: progress)
                }
        }
    }

    private struct JSONData: Content {
        let data: Data
    }
    
    private func keyExchange(req: HTTPRequest, channel: Channel, handler: RequestHandler) -> EventLoopFuture<Void> {
        self.logger?.trace("Inline.Client-密钥交换中: 创建公私钥对")
        let keyPair = Crypto.Asym.makeCryptoKeyPair()
        self.logger?.trace("Inline.Client-密钥交换中: 将公钥发送于目标")
        guard let body = try? JSONEncoder().encode(JSONData(data: keyPair.public.data())) else { return channel.eventLoop.makeFailedFuture(Inline.RequestInternalErr.unknowSendError.d("JSON 编码失败", 13003)) }
        return self.send(.init(method: .POST, url: req.url, headers: ["content-type": "application/json"], body: .init(data: body)), channel: channel, handler: handler, bufferStrategy: .collect, progress: { _ in }).flatMapThrowing { response in
            // 检查对方的响应，对方应当发来自己的公钥
            self.logger?.trace("Inline.Client-密钥交换中: 检查对方发来的公钥")
            guard response.status == .ok else { throw Inline.RequestErr.unknowError.d("\(response.status.description)(\(response.status.code))", 10090).adds(.internalServerError) }
            guard let data = response.body?.data() else { throw Inline.RequestErr.targetIncorrectResponseBody.d("预期为公钥，但得到不正确回复", 10091).adds(.internalServerError) }
            self.logger?.trace("Inline.Client-密钥交换中: 解包对方发来的公钥")
            let targetPub = try Crypto.Asym.CPublicKey(data: data)
            self.logger?.trace("Inline.Client-密钥交换中: 计算共享密钥")
            let sharedKey = try Crypto.Asym.keyEncapsulate(key: keyPair.private, partyPublic: targetPub, salt: Crypto.hash("inline.shared.key"), info: "")
            self.logger?.trace("Inline.Client-密钥交换中: 设置标志位")
            self.requestIoData.connectionKeys[ObjectIdentifier(channel)] = sharedKey
        }.flatMapError { err in
            if let err = err as? HTTPResponseError {
                return channel.eventLoop.makeFailedFuture(err)
            } else {
                return channel.eventLoop.makeFailedFuture(Inline.RequestErr.unknowError.d(15020).subErr(err).adds(.internalServerError))
            }
        }
    }
    
    private func serviceValidate(req: HTTPRequest, channel: Channel, handler: RequestHandler) -> EventLoopFuture<Void> {
        self.logger?.trace("Inline.Client-进行服务验证: 将自己的服务 ID 发送于目标")
        guard let body = try? JSONEncoder().encode(JSONData(data: self.requestIoData.serviceID.data())) else { return channel.eventLoop.makeFailedFuture(Inline.RequestInternalErr.unknowSendError.d("JSON 编码失败", 13004)) }
        return self.send(.init(method: .POST, url: req.url, headers: ["content-type": "application/json"], body: .init(data: body)), channel: channel, handler: handler, bufferStrategy: .collect, progress: { _ in }).flatMapThrowing { response in
            self.logger?.trace("Inline.Client-进行服务验证: 检查对方的响应")
            guard response.status == .ok else { throw Inline.RequestErr.unknowError.d("\(response.status.description)", 10092).adds(response.status) }
            self.logger?.trace("Inline.Client-进行服务验证: 设置标志位")
            self.requestIoData.connectionValidate[ObjectIdentifier(channel)] = true
        }.flatMapError { err in
            if let err = err as? HTTPResponseError {
                return channel.eventLoop.makeFailedFuture(err)
            } else {
                return channel.eventLoop.makeFailedFuture(Inline.RequestErr.unknowError.d(15021).subErr(err).adds(.internalServerError))
            }
        }
    }
}
