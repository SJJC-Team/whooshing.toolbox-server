import Vapor
import WhooshingClient

/// 该文件实现了发送加密请求的功能。由于目标模块的加密算法并非传统的 HTTPS，
/// 而是自定的加密算法，因此向其请求时需要使用特定的加密逻辑。

final class InlineClient: ReqClient<Inline.RequestIOCrypto>, WhooshingClient, @unchecked Sendable {
    typealias Errcase = InlineClientErrcase
    
    var key: SendableSymmKey? {
        guard
            let ioData = self.storage[Inline.RequestIOData.self],
            let channel = self.channel,
            let key = ioData.connectionKeys[ObjectIdentifier(channel)]
        else { return nil }
        return key
    }
    
    func send(
        _ request: HTTPRequest
    ) -> EventLoopResult<HTTPResponse, Failure> {
        self.makeChannel(url: request.url)
            .errCast(Errcase.tcpChannelAssignFailed, category: .inherit)
            .flatMap
        { channel, handler, _ in
            self.logger?.info("Inline.Client-发送请求", metadata: ["client_addr": .string(channel.clientAddrInfo)])
            self.logger?.debug("请求内容", metadata: ["request": .data(request)])
            return self._send(request: request, channel: channel, handler: handler).map { res in
                self.logger?.info("发送请求成功，收到响应", metadata: ["status": .stringConvertible(res.status)])
                self.logger?.debug("响应内容", metadata: ["response": .data(res)])
                return res
            }
        }.logIfFailAndExist(logger: logger)
    }
    
    func removeHTTPHandlers() async -> Result<Void, Failure> {
        await super.removeHTTPHandlers().mapError(as: Errcase.tcpHandleRemoveFailed, category: .inherit)
    }
    
    func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopResult<Void, Failure> {
        super.removeHTTPHandlers(in: eventLoop).errCast(Errcase.tcpHandleRemoveFailed, category: .inherit)
    }
    
    /// 关闭所有正在进行的连线
    @inlinable
    public func shutdown() async throws {
        logger?.info("Inline.Client-主动关闭连接", metadata: ["client_addr": .stringConvertible(channel?.clientAddrInfo ?? "released")])
        await self.close()
    }
    
    @inlinable
    public func syncShutdown() throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = Box()
        Task.detached {
            do {
                try await self.shutdown()
            } catch {
                errorBox.error = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let e = errorBox.error { throw e }
    }
    
    deinit {
        Task { [weak self] in
            self?.logger?.debug("Inline.Client-主动关闭连接")
            await self?.close()
        }
    }
}

extension InlineClient {
    private func _send(
        request: HTTPRequest,
        channel: Channel,
        handler: RequestWrapperHandler
    ) -> EventLoopResult<HTTPResponse, Failure> {
        let id = ObjectIdentifier(channel)
        let procedure: Int
        if self.requestIoData.connectionKeys[id] == nil { procedure = 0 }
        else if self.requestIoData.connectionValidate[id] != true { procedure = 1 }
        else { procedure = 2 }
        var r = channel.eventLoop.makeSucceededVoidResult(throws: Failure.self)
        switch (procedure) {
            case 0:
                r = r.flatMap {
                    self.logger?.debug("Inline.Client-与服务器首次请求，进行密钥交换", metadata: ["client_addr": .string(channel.clientAddrInfo)])
                    return self.keyExchange(req: request, channel: channel, handler: handler)
                }
                fallthrough
            case 1:
                r = r.flatMap {
                    self.logger?.debug("Inline.Client-与服务器配合进行服务验证", metadata: ["client_addr": .string(channel.clientAddrInfo)])
                    return self.serviceValidate(req: request, channel: channel, handler: handler)
                }
                fallthrough
            default:
                return r.flatMap {
                    self.logger?.debug("Inline.Client-与服务器发送真正请求", metadata: ["client_addr": .string(channel.clientAddrInfo)])
                    return self.send(request, channel: channel, handler: handler).errCast(Errcase.tcpSendFailed, "发送用户请求失败", category: .inherit)
                }
        }
    }

    private struct JSONData: Content {
        let data: Data
    }
    
    private func keyExchange(
        req: HTTPRequest,
        channel: Channel,
        handler: RequestWrapperHandler
    ) -> EventLoopResult<Void, Failure> {
        channel.eventLoop.submitResult { () throws(Failure) in
            self.logger?.debug("Inline.Client-密钥交换中: 创建公私钥对")
            let keyPair = Crypto.Asym.makeCryptoKeyPair()
            
            self.logger?.debug("Inline.Client-密钥交换中: 编码 json 数据")
            let body = try required(throws: Errcase.jsonEncodeFailed, category: .inherit) {
                try HTTPBody.json(JSONData(data: keyPair.public.data)).get()
            }
            
            self.logger?.debug("Inline.Client-密钥交换中: 将公钥发送于目标")
            return (
                HTTPRequest(method: .POST, url: req.url, body: body),
                (public: SendableAsymCPublicKey(key: keyPair.public), private: SendableAsymCPrivateKey(key: keyPair.private))
            )
        }.flatMap { (req, keyPair: (public: SendableAsymCPublicKey, private: SendableAsymCPrivateKey)) in
            self.send(req, channel: channel, handler: handler).errCast(Errcase.tcpSendFailed, category: .inherit).map { ($0, keyPair) }
        }.flatMapThrowing { res, keyPair throws(Failure) in
            // 检查对方的响应，对方应当发来自己的公钥
            self.logger?.debug("Inline.Client-密钥交换中: 检查对方发来的公钥")
            guard res.status == .ok else {
                throw Errcase.badResponse.d("响应状态码为: \(res.status)", category: .internal)
            }
            
            guard let resBody = res.body else {
                throw Errcase.badResponse.d("响应体为空", category: .internal)
            }
            
            self.logger?.debug("Inline.Client-密钥交换中: 解析对方的公钥")
            let data = try required(throws: Errcase.dataDecodeFailed, category: .internal) {
                try resBody.data(as: Data.self).get()
            }
            
            self.logger?.debug("Inline.Client-密钥交换中: 解包对方发来的公钥")
            let targetPub = try required(throws: Errcase.decryptFailed, category: .internal) {
                try Crypto.Asym.CPublicKey.make(data: data).get()
            }
            
            self.logger?.debug("Inline.Client-密钥交换中: 计算共享密钥")
            let sharedKey: SendableSymmKey = try required(throws: Errcase.keyEncapsulateFailed, category: .inherit) {
                try .init(key: Crypto.Asym.keyEncapsulate(
                    key: keyPair.private.key,
                    partyPublic: targetPub,
                    salt: Crypto.hash("inline.shared.key").get(),
                    info: ""
                ).get())
            }
            
            self.logger?.debug("Inline.Client-密钥交换中: 设置标志位")
            self.requestIoData.connectionKeys[ObjectIdentifier(channel)] = sharedKey
        }
    }
    
    private func serviceValidate(
        req: HTTPRequest,
        channel: Channel,
        handler: RequestWrapperHandler
    ) -> EventLoopResult<Void, Failure> {
        channel.eventLoop.submitResult { () throws(Failure) in
            self.logger?.debug("Inline.Client-进行服务验证: 将自己的服务 ID 发送于目标")
            let body = try required(throws: Errcase.jsonEncodeFailed, category: .inherit) {
                try HTTPBody.json(JSONData(data: self.requestIoData.serviceID.data)).get()
            }
            
            return HTTPRequest(method: .POST, url: req.url, body: body)
        }.flatMap { req in
            self.send(req, channel: channel, handler: handler).errCast(Errcase.tcpSendFailed, category: .inherit)
        }.flatMapThrowing { res throws(Failure) in
            self.logger?.debug("Inline.Client-进行服务验证: 检查对方的响应")
            guard res.status == .ok else {
                throw Errcase.badResponse.d("响应状态码为: \(res.status)", category: .internal)
            }
            
            self.logger?.debug("Inline.Client-进行服务验证: 设置标志位")
            self.requestIoData.connectionValidate[ObjectIdentifier(channel)] = true
        }
    }
}
