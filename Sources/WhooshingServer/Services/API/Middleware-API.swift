import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging
import WhooshingClient

public extension API {
    enum ProtocolErr: String, ErrList {
        public typealias ErrType = HTTPResponseError
        public var domain: String { "woo.api.sys.middleware.guard.err" }
        case unknowError = "未知错误"
        case requestFailed = "向认证模块请求失败"
    }
}

extension API {
    struct GuardMiddleware: Middleware {
        let authenticationURL: URL
        let debugingAuth: Debuging.Auth?

        func respond(to req: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {
            guard let channel = req.channel else { return req.eventLoop.makeFailedFuture(API.ProtocolErr.unknowError.d("未找到 Channel", 14006).adds(.internalServerError)) }
            let id = ObjectIdentifier(channel)
            if let _ = req.application.apiServiceData.clientKeys[id] {
                req.logger.debug("API.Server-处理客户端的真正请求: \(channel.serverAddrInfo)")
                return next.respond(to: req)
            } else {
                req.logger.debug("API.Server-与客户端交换密钥: \(channel.serverAddrInfo)")
                return keyExchange(req: req, channel: channel)
            }
        }

        struct JSONData: Content {
            let data: Data
        }

        @Sendable private func keyExchange(req: Request, channel: Channel) -> EventLoopFuture<Response> {
            let authData: AuthExchangeData
            do {
                authData = try req.content.decode(AuthExchangeData.self)
            } catch let err {
                return channel.eventLoop.makeFailedFuture(err)
            }
            let id = ObjectIdentifier(channel)
            
            let r: EventLoopFuture<Crypto.Symm.Key>
            if let debuging = debugingAuth {
                req.logger.notice("API.Server-进行用户身份认证 (Testing, 并不实际向认证模块请求认证)")
                r = channel.eventLoop.submit { try debuging(authData) }
            } else {
                req.logger.trace("API.Server-与客户端密钥交换: 向认证模块发送认证请求")
                r = req.application.apiServiceData.inlineClient.asyncPost(
                    authenticationURL.toUri(with: "/user/auth"),
                    beforeSend: { req, _ in try req.jsonBodyEncode(authData) },
                    afterSend: InlineClient.defaultAfterSend
                )
                .hop(to: channel.eventLoop)
                .flatMapThrowing { res in
                    guard res.status == .ok else { throw API.ProtocolErr.requestFailed.d("请求的状态码结果为: \(res.status), 结果为: \(res.body != nil ? String(buffer: res.body!) : "nil")", 12001).adds(.internalServerError) }
                    req.logger.trace("API.Server-与客户端密钥交换: 从认证模块返回的结果解析用户口令")
                    let token = try res.jsonBodyDecode(Crypto.Symm.Key.self)
                    return token
                }
            }
            
            return r.flatMapThrowing { token in
                req.logger.trace("API.Server-与客户端密钥交换: 生成新的密钥，用做通讯加密")
                let newKey = Crypto.Symm.makeKey()
                req.logger.trace("API.Server-与客户端密钥交换: 将新密钥使用用户口令加密，作为响应直接返回给客户端")
                let newKeyEncrypted = try Crypto.Symm.encrypt(newKey, key: token)
                req.logger.trace("API.Server-与客户端密钥交换: 临时使用用户口令加密新密钥，确保客户端可以解开")
                req.application.apiServiceData.clientTokens[id] = token
                req.logger.trace("API.Server-与客户端密钥交换: 将新密钥注册，用于将来该客户端所有的通讯加密")
                req.application.apiServiceData.clientKeys[id] = newKey
                let body = try JSONEncoder().encode(JSONData(data: newKeyEncrypted))
                return .init(status: .ok, version: .http1_1, headers: ["content-type": "application/json"], body: .init(data: body))
            }
            .flatMapError { err in
                return channel.eventLoop.makeFailedFuture(err)
            }
        }
    }

}

fileprivate extension Application {
    var apiServiceData: API.ServiceData! { self.storage[API.ServiceData.self] }
}
