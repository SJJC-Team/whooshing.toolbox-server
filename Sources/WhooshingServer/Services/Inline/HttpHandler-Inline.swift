import Vapor
import WhooshingClient
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging

/// 该文件从 Http 的基层 TCP 的层级上配置加密中间件，使得服务使用自定加密算法，
/// 而非默认的 HTTPS。使用自定加密算法，这也意味着将不受浏览器的支持，
/// 因此，若配置了该加密中间件，则无法在浏览器上访问该服务

extension Application {
    var inlineServiceData: Inline.ServiceData! { self.storage[Inline.ServiceData.self] }
}

extension Inline {
    final class ServiceData: StorageKey, Sendable {
        typealias Value = ServiceData
        let rootKey: Crypto.Symm.Key
        let moduleDatas: [ModuleData]
        let connectionValidate: SendableDictionary<ObjectIdentifier, Bool> = .init()
        let connectionKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        
        init(rootKey: Crypto.Symm.Key, moduleDatas: [ModuleData]) {
            self.rootKey = rootKey
            self.moduleDatas = moduleDatas
        }
    }
    
    /// 实现 HTTP IO 加解密处理
    struct HttpIOCrypto: HTTPIOHandler, Sendable {
        let app: Application
        /// 有客户端请求进入
        func input(request: Data, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<Data?> {
            let id = ObjectIdentifier(context.channel)
            let req: Data
            do {
                app.logger.trace("Inline.HTTP-客户端请求进入，进行解密(key: \(app.inlineServiceData.connectionKeys[id] != nil)) in \(context.channel.serverAddrInfo)")
                if let key = app.inlineServiceData.connectionKeys[id] { req = try Crypto.Symm.decrypt(request, key: key) }
                else { req = try Crypto.Symm.decrypt(request, key: app.inlineServiceData.rootKey) }
                return context.eventLoop.makeSucceededFuture(req)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }
        
        /// 有服务器响应请求发出
        func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo, streaming: Bool) -> EventLoopFuture<Data> {
            let id = ObjectIdentifier(context.channel)
            let res: Data
            do {
                app.logger.trace("Inline.HTTP-客户端响应发出，进行加密(key: \(app.inlineServiceData.connectionKeys[id] != nil), validated: \(app.inlineServiceData.connectionValidate[id] != nil)) in \(context.channel.serverAddrInfo)")
                // 若 key 存在，但 validate 不存在，则仍然使用 rootKey 加密
                if let key = app.inlineServiceData.connectionKeys[id], let _ = app.inlineServiceData.connectionValidate[id] {
                    res = try Crypto.Symm.encrypt(response, key: key)
                } else { res = try Crypto.Symm.encrypt(response, key: app.inlineServiceData.rootKey) }
                return context.eventLoop.makeSucceededFuture(res)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }
        
        /// 连线建立
        func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            app.logger.debug("Inline.Server-连线建立: \(context.channel.serverAddrInfo)")
            return context.eventLoop.makeSucceededVoidFuture()
        }
        
        /// 连线结束
        func connectionEnd(context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Void> {
            app.logger.debug("Inline.Server-连线结束: \(context.channel.serverAddrInfo)")
            let id = ObjectIdentifier(context.channel)
            app.inlineServiceData.connectionKeys[id] = nil
            app.inlineServiceData.connectionValidate[id] = nil
            return context.eventLoop.makeSucceededVoidFuture()
        }
    }
}
