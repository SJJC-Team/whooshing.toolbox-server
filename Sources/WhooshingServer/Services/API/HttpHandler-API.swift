import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging
import WhooshingClient

/// 该文件实现了 API 模块接收和发出的加密机制 Socket 流处理
/// 每个 API 请求前必须经过身份验证

extension Application {
    var apiServiceData: API.ServiceData! { self.storage[API.ServiceData.self] }
}

extension API {
    
    final class ServiceData: StorageKey, Sendable {
        typealias Value = ServiceData
        let inlineClient: InlineReqClient
        let clientKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        let clientTokens: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()

        init(inlineClient: InlineReqClient) {
            self.inlineClient = inlineClient
        }
    }
    
    struct HttpIOCrypto: HTTPIOHandler, Sendable {
        let app: Application
        let authenticationURL: URL
        
        /// 有客户端请求进入
        func input(request: Data, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<Data?> {
            let id = ObjectIdentifier(context.channel)
            do {
                app.logger.trace("API.HTTP-客户端请求进入，进行解密(key: \(app.apiServiceData.clientKeys[id] != nil)) in \(context.channel.serverAddrInfo)")
                let req: Data
                if let key = app.apiServiceData.clientKeys[id] {
                    req = try Crypto.Symm.decrypt(request, key: key)
                } else {
                    // 客户端第一次连线的认证请求
                    // 这里对方将发送明文，因为用户凭据可明文发送，而用户口令会加密处理
                    req = request
                }
                return context.eventLoop.makeSucceededFuture(req)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }
        
        /// 有服务器响应请求发出
        func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo, streaming: Bool) -> EventLoopFuture<Data> {
            let id = ObjectIdentifier(context.channel)
            do {
                app.logger.trace("API.HTTP-客户端响应发出，进行加密(temp: \(app.apiServiceData.clientTokens[id] != nil), key: \(app.apiServiceData.clientKeys[id] != nil)) in \(context.channel.serverAddrInfo)")
                let res: Data
                // 使用 clientTokens 加密，是临时的，仅仅是作为服务器第一次响应时的加密密钥
                if let key = app.apiServiceData.clientTokens[id] {
                    res = try Crypto.Symm.encrypt(response, key: key)
                    if !streaming { app.apiServiceData.clientTokens[id] = nil }
                } else if let key = app.apiServiceData.clientKeys[id] {
                    res = try Crypto.Symm.encrypt(response, key: key)
                } else { 
                    res = response
                }
                return context.eventLoop.makeSucceededFuture(res)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }
        
        func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            app.logger.debug("API.Server-连线建立: \(context.channel.serverAddrInfo)")
            return context.eventLoop.makeSucceededVoidFuture()
        }

        /// 连线结束
        func connectionEnd(context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Void> {
            app.logger.debug("API.Server-连线结束: \(context.channel.serverAddrInfo)")
            let id = ObjectIdentifier(context.channel)
            app.apiServiceData.clientKeys[id] = nil
            app.apiServiceData.clientTokens[id] = nil
            return context.eventLoop.makeSucceededVoidFuture()
        }
    }
}
