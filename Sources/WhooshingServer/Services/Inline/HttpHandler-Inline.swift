import Vapor
import WhooshingClient

/// 该文件从 Http 的基层 TCP 的层级上配置加密中间件，使得服务使用自定加密算法，
/// 而非默认的 HTTPS。使用自定加密算法，这也意味着将不受浏览器的支持，
/// 因此，若配置了该加密中间件，则无法在浏览器上访问该服务

extension Whooshing where Service == Inline {
    var inlineServiceData: Inline.ServiceData! { self.app.storage[Inline.ServiceData.self] }
}

extension Inline {
    @frozen
    public enum CryptoErrcase: String, ErrList, Sendable {
        case requestDecryptFailed = "请求数据解密失败"
        case responseEncryptFailed = "响应数据加密失败"
        case internalFailure = "内部错误"
    }
    
    final class ServiceData: StorageKey, Sendable {
        typealias Value = ServiceData
        let rootKey: SendableSymmKey
        let moduleDatas: [ModuleData]
        let connectionValidate: SendableDictionary<ObjectIdentifier, Bool> = .init()
        let connectionKeys: SendableDictionary<ObjectIdentifier, SendableSymmKey> = .init()
        
        init(rootKey: SendableSymmKey, moduleDatas: [ModuleData]) {
            self.rootKey = rootKey
            self.moduleDatas = moduleDatas
        }
    }
    
    /// 实现 HTTP IO 加解密处理
    struct HttpIOCrypto: HTTPIOHandler, Sendable {
        weak var app: Whooshing<Inline>!
        
        /// 有客户端请求进入
        func input(request: Data, context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Data, CryptoErrcase> {
            logger.debug("Inline.HTTP-客户端请求进入，进行解密", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
            guard request.count > 0 else {
                logger.debug("请求数据为空，忽略")
                return context.eventLoop.makeSucceededResult(request)
            }
            let id = ObjectIdentifier(context.channel)
            let req: Data
            do {
                if let key = app.inlineServiceData.connectionKeys[id] {
                    logger.debug("使用已有密钥解密通讯")
                    req = try required(throws: CryptoErrcase.requestDecryptFailed) {
                        try Crypto.Symm.decrypt(request, key: key.key).get()
                    }
                } else {
                    logger.debug("首次请求，使用根密钥解密")
                    req = try required(throws: CryptoErrcase.requestDecryptFailed) {
                        try Crypto.Symm.decrypt(request, key: app.inlineServiceData.rootKey.key).get()
                    }
                }
                
                return context.eventLoop.makeSucceededResult(req)
            } catch {
                return context.eventLoop.makeFailedResult(error)
            }
        }
        
        /// 有服务器响应请求发出
        func output(response: Data, context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Data, CryptoErrcase> {
            logger.debug("Inline.HTTP-客户端响应发出，进行加密", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
            guard response.count > 0 else {
                logger.debug("响应数据为空，忽略")
                return context.eventLoop.makeSucceededResult(response) }
            let id = ObjectIdentifier(context.channel)
            let res: Data
            do {
                // 若 key 存在，但 validate 不存在，则仍然使用 rootKey 加密
                if let key = app.inlineServiceData.connectionKeys[id], let _ = app.inlineServiceData.connectionValidate[id] {
                    logger.debug("使用已有密钥进行加密")
                    res = try required(throws: CryptoErrcase.responseEncryptFailed) {
                        try Crypto.Symm.encrypt(response, key: key.key).get()
                    }
                } else {
                    logger.debug("首次发送响应，使用根密钥加密响应")
                    res = try required(throws: CryptoErrcase.responseEncryptFailed) {
                        try Crypto.Symm.encrypt(response, key: app.inlineServiceData.rootKey.key).get()
                    }
                }
                return context.eventLoop.makeSucceededResult(res)
            } catch {
                return context.eventLoop.makeFailedResult(error)
            }
        }
        
        /// 连线建立
        func connectionStart(context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Void, CryptoErrcase> {
            logger.debug("Inline.Server-连线建立", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
            return context.eventLoop.makeSucceededVoidResult()
        }
        
        /// 连线结束
        func connectionEnd(context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Void, CryptoErrcase> {
            let id = ObjectIdentifier(context.channel)
            if let app = self.app {
                logger.debug("Inline.Server-连线结束", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
                app.inlineServiceData.connectionKeys[id] = nil
                app.inlineServiceData.connectionValidate[id] = nil
            }
            return context.eventLoop.makeSucceededVoidResult()
        }
    }
}
