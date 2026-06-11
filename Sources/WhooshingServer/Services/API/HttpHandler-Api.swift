import Vapor
import NIO
import NIOAdvanced
import Logging
import Cryptos
import ErrorHandle
import DataConvertable
import WhooshingClient

/// 该文件实现了 API 模块接收和发出的加密机制 Socket 流处理
/// 每个 API 请求前必须经过身份验证

extension Whooshing where Service == Api {
    var apiServiceData: Api.ServiceData! { self.app.storage[Api.ServiceData.self] }
}

extension Api {
    @frozen
    public enum CryptoErrcase: String, ErrList, Sendable {
        case requestDecryptFailed = "请求数据解密失败"
        case responseEncryptFailed = "响应数据加密失败"
        case internalFailure = "内部错误"
    }
    
    final class ServiceData: StorageKey, Sendable {
        typealias Value = ServiceData
        unowned let inlineClient: AnyWhooshingClient<InlineClientErrcase>
        let clientKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        let clientTokens: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()

        init(inlineClient: AnyWhooshingClient<InlineClientErrcase>) {
            self.inlineClient = inlineClient
        }
    }
    
    struct HttpIOCrypto: HTTPIOHandler, Sendable {
        weak var app: Whooshing<Api>!
        
        /// 有客户端请求进入
        func input(request: Data, context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Data, CryptoErrcase> {
            logger.debug("API.HTTP-客户端请求进入，进行解密", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
            guard request.count > 0 else {
                logger.debug("请求数据为空，忽略")
                return context.eventLoop.makeSucceededResult(request)
            }
            let id = ObjectIdentifier(context.channel)
            let req: Data
            do {
                if let key = app.apiServiceData.clientKeys[id] {
                    logger.debug("使用已有密钥解密通讯")
                    req = try required(throws: CryptoErrcase.requestDecryptFailed) {
                        try Crypto.Symm.decrypt(request, key: key).get()
                    }
                } else {
                    logger.debug("首次请求，直接读取明文凭据")
                    // 客户端第一次连线的认证请求
                    // 这里对方将发送明文，因为用户凭据可明文发送，而用户口令会加密处理
                    req = request
                }
                return context.eventLoop.makeSucceededResult(req)
            } catch {
                return context.eventLoop.makeFailedResult(error)
            }
        }
        
        /// 有服务器响应请求发出
        func output(response: Data, context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Data, CryptoErrcase> {
            logger.debug("API.HTTP-客户端响应发出，进行加密", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
            let id = ObjectIdentifier(context.channel)
            guard response.count > 0 else {
                logger.debug("响应数据为空，忽略")
                app.apiServiceData.clientTokens[id] = nil
                return context.eventLoop.makeSucceededResult(response)
            }
            let res: Data
            do {
                // 使用 clientTokens 加密，是临时的，仅仅是作为服务器第一次响应时的加密密钥
                if let key = app.apiServiceData.clientTokens[id] {
                    logger.debug("首次发送响应，使用该 client 的默认密钥加密响应")
                    res = try required(throws: CryptoErrcase.responseEncryptFailed) {
                        try Crypto.Symm.encrypt(response, key: key).get()
                    }
                } else if let key = app.apiServiceData.clientKeys[id] {
                    logger.debug("使用已有密钥进行加密")
                    res = try required(throws: CryptoErrcase.responseEncryptFailed) {
                        try Crypto.Symm.encrypt(response, key: key).get()
                    }
                } else {
                    res = response
                }
                return context.eventLoop.makeSucceededResult(res)
            } catch {
                return context.eventLoop.makeFailedResult(error)
            }
        }
        
        func connectionStart(context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Void, CryptoErrcase> {
            logger.debug("API.Server-连线建立", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
            return context.eventLoop.makeSucceededVoidResult()
        }

        /// 连线结束
        func connectionEnd(context: ChannelHandlerContext, logger: Logger) -> EventLoopRes<Void, CryptoErrcase> {
            let id = ObjectIdentifier(context.channel)
            if let app = self.app {
                logger.debug("API.Server-连线结束", metadata: ["server_addr": .string(context.channel.serverAddrInfo)])
                app.apiServiceData.clientKeys[id] = nil
                app.apiServiceData.clientTokens[id] = nil
            }
            return context.eventLoop.makeSucceededVoidResult()
        }
    }
}
