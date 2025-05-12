import Vapor
import ErrorHandle
import DataConvertable
import NIOCore
import Logging
import Cryptos
import WhooshingClient

/// 该文件实现了发送加密请求的功能。由于目标模块的加密算法并非传统的 HTTPS，
/// 而是自定的加密算法，因此向其请求时需要使用特定的加密逻辑。

final class InlineReqClient: ReqClient, WhooshingClient, StorageKey, @unchecked Sendable {
    
    typealias Value = InlineReqClient

    enum InlineReqErr: String, ErrList {
        var domain: String { "woo.sys.inline.reqclient.err" }
        case targetBadResponse = "目标返回了不正常的响应"
        case targetIncorrectResponseBody = "目标的响应体不正确"
        case unknowSendError = "发送时遇到未知错误"
    }
    
    @Sendable 
    func send(
        _ method: HTTPMethod,
        headers: HTTPHeaders,
        to url: URI,
        bufferStrategy: BufferStrategy,
        beforeSend: @escaping BeforeSendAction,
        afterSend: @escaping AsyncAfterSendAction,
        progress: @escaping ProgressAction
    ) -> EventLoopFuture<ClientResponse?> {
        let req = ClientRequest(method: method, url: url, headers: headers, body: nil, byteBufferAllocator: self.byteBufferAllocator)
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
                return self._send(request: request, bufferStrategy: bufferStrategy, channel: channel, handler: handler, progress: progress).flatMapError { err in
                    return channel.eventLoop.makeFailedFuture(err)
                }.flatMap { res in
                    afterSend(channel).map { res }
                }
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
    }
    
    private func _send(request: ClientRequest, bufferStrategy: BufferStrategy, channel: Channel, handler: RequestHandler, progress: @escaping @Sendable (ProgressContext<ClientResponse?>) throws -> Void) -> EventLoopFuture<ClientResponse?> {
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
                }.flatMapError { err in
                    return channel.eventLoop.makeFailedFuture(InlineReqErr.unknowSendError.d(10095, (#file, #line)).subErr(err))
                }
        }
    }

    private struct JSONData: Content {
        let data: Data
    }
    
    private func keyExchange(req: ClientRequest, channel: Channel, handler: RequestHandler) -> EventLoopFuture<Void> {
        self.logger?.trace("Inline.Client-密钥交换中: 创建公私钥对")
        let keyPair = Crypto.Asym.makeCryptoKeyPair()
        self.logger?.trace("Inline.Client-密钥交换中: 将公钥发送于目标")
        guard let body = try? JSONEncoder().encode(JSONData(data: keyPair.public.data())) else { return channel.eventLoop.makeFailedFuture(InlineReqErr.unknowSendError.d("JSON 编码失败", 13003, (#file, #line))) }
        return self.send(.init(method: .POST, url: req.url, headers: ["content-type": "application/json"], body: .init(data: body)), channel: channel, handler: handler, bufferStrategy: .collect, progress: { _ in }).flatMapThrowing { response in 
            // 此处 response 必定有值，因为 BufferStrategy 是 .collect
            let response = response!
            // 检查对方的响应，对方应当发来自己的公钥
            self.logger?.trace("Inline.Client-密钥交换中: 检查对方发来的公钥")
            guard response.status == .ok else { throw InlineReqErr.targetBadResponse.d("\(response.status.description)(\(response.status.code))", 10090, (#file, #line)) }
            guard let data = response.body?.data() else { throw InlineReqErr.targetIncorrectResponseBody.d("预期为公钥，但得到不正确回复", 10091, (#file, #line)) }
            self.logger?.trace("Inline.Client-密钥交换中: 解包对方发来的公钥")
            let targetPub = try Crypto.Asym.CPublicKey(data: data)
            self.logger?.trace("Inline.Client-密钥交换中: 计算共享密钥")
            let sharedKey = try Crypto.Asym.keyEncapsulate(key: keyPair.private, partyPublic: targetPub, salt: Crypto.hash("inline.shared.key"), info: "")
            self.logger?.trace("Inline.Client-密钥交换中: 设置标志位")
            self.requestIoData.connectionKeys[ObjectIdentifier(channel)] = sharedKey
        }.flatMapError { err in 
            return channel.eventLoop.makeFailedFuture(err)
        }
    }
    
    private func serviceValidate(req: ClientRequest, channel: Channel, handler: RequestHandler) -> EventLoopFuture<Void> {
        self.logger?.trace("Inline.Client-进行服务验证: 将自己的服务 ID 发送于目标")
        guard let body = try? JSONEncoder().encode(JSONData(data: self.requestIoData.serviceID.data())) else { return channel.eventLoop.makeFailedFuture(InlineReqErr.unknowSendError.d("JSON 编码失败", 13004, (#file, #line))) }
        return self.send(.init(method: .POST, url: req.url, headers: ["content-type": "application/json"], body: .init(data: body)), channel: channel, handler: handler, bufferStrategy: .collect, progress: { _ in }).flatMapThrowing { response in
            // 此处 response 必定有值，因为 BufferStrategy 是 .collect
            let response = response!
            self.logger?.trace("Inline.Client-进行服务验证: 检查对方的响应")
            guard response.status == .ok else { throw InlineReqErr.targetBadResponse.d("\(response.status.description)(\(response.status.code))", 10092, (#file, #line)) }
            self.logger?.trace("Inline.Client-进行服务验证: 设置标志位")
            self.requestIoData.connectionValidate[ObjectIdentifier(channel)] = true
        }.flatMapError { err in
            return channel.eventLoop.makeFailedFuture(err)
        }
    }

    deinit {
        Task { [weak self] in
            self?.logger?.debug("Inline.Client-主动关闭连接")
            await self?.closeAll()
        }
    }
}
