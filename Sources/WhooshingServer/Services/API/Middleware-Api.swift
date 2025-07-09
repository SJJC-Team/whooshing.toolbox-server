import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import NIOAdvanced
import Logging
import WhooshingClient

extension Api {
    struct GuardMiddleware: Middleware {
        let authenticationURL: URL
        let debugingAuth: Debuging.Auth?

        func respond(to req: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {
            guard let channel = req.channel else {
                return req.eventLoop.makeFailedFuture(Errcase.internalFailure.d("未找到 Channel"))
            }
            let id = ObjectIdentifier(channel)
            if let _ = req.application.apiServiceData.clientKeys[id] {
                req.logger.debug("API.Server-处理客户端的真正请求: \(channel.serverAddrInfo)")
                return next.respond(to: req)
            } else {
                req.logger.debug("API.Server-与客户端交换密钥: \(channel.serverAddrInfo)")
                return keyExchange(req: req, channel: channel).wrapped
            }
        }

        struct JSONData: Content {
            let data: Data
        }

        @Sendable private func keyExchange(req: Request, channel: Channel) -> EventLoopResult<Response, Failure> {
            enum ParaResult {
                case real(HTTPBody)
                case debugging(Api.Debuging.Auth)
            }
            
            return req.eventLoop.submitResult { () throws(Failure) in
                let authData = try required(throws: Errcase.authDataDecodeFailed) {
                    try req.content.decode(AuthExchangeData.self)
                }
                
                let result: ParaResult
                
                if let debuging = debugingAuth {
                    result = .debugging(debuging)
                } else {
                    result = .real(
                        try required(throws: Errcase.jsonEncodeFailed) {
                            try HTTPBody.json(authData).get()
                        }
                    )
                }
                
                return (authData, result)
            }.flatMap { (authData: AuthExchangeData, result: ParaResult) -> EventLoopResult<Debuging.UserToken, Failure> in
                switch result {
                case .debugging(let debugging):
                    req.logger.notice("API.Server-进行用户身份认证 (Testing, 并不实际向认证模块请求认证)")
                    return req.eventLoop.submitResult { () throws(Failure) in
                        try required(throws: Errcase.authFailed) {
                            try debugging(authData)
                        }
                    }
                case .real(let body):
                    req.logger.trace("API.Server-与客户端密钥交换: 向认证模块发送认证请求")
                    return req.application.apiServiceData.inlineClient.post(
                        authenticationURL.toUri(with: "/user/auth"),
                        body: body
                    )
                    .errCast(Errcase.internalFailure, "向认证模块请求认证失败，未知错误")
                    .hop(to: req.eventLoop)
                    .flatMapThrowing { res throws(Failure) in
                        guard res.status == .ok else {
                            throw Errcase.internalFailure.d("认证模块响应异常，其响应的状态码结果为: \(res.status)")
                        }
                        
                        req.logger.trace("API.Server-与客户端密钥交换: 从认证模块返回的结果解析用户口令")
                        guard let resBody = res.body else {
                            throw Errcase.internalFailure.d("认证模块响应异常，响应体为空")
                        }
                        
                        let token = try required(throws: Errcase.internalFailure, "认证模块响应异常，响应体解析用户口令失败") {
                            try resBody.json(as: Crypto.Symm.Key.self).get()
                        }
                        
                        return token
                    }
                }
            }.flatMapThrowing { token throws(Failure) in
                let id = ObjectIdentifier(channel)
                req.logger.trace("API.Server-与客户端密钥交换: 生成新的密钥，用做通讯加密")
                let newKey = Crypto.Symm.makeKey()
                req.logger.trace("API.Server-与客户端密钥交换: 将新密钥使用用户口令加密，作为响应直接返回给客户端")
                let newKeyEncrypted = try required(throws: Errcase.jsonDecodeFailed) {
                    try Crypto.Symm.encrypt(newKey, key: token).get()
                }
                req.logger.trace("API.Server-与客户端密钥交换: 临时使用用户口令加密新密钥，确保客户端可以解开")
                req.application.apiServiceData.clientTokens[id] = token
                req.logger.trace("API.Server-与客户端密钥交换: 将新密钥注册，用于将来该客户端所有的通讯加密")
                req.application.apiServiceData.clientKeys[id] = newKey
                let body = try required(throws: Errcase.jsonEncodeFailed) {
                    try JSONEncoder().encode(JSONData(data: newKeyEncrypted))
                }
                return .init(
                    status: .ok,
                    version: .http1_1,
                    headers: ["content-type": "application/json"],
                    body: .init(data: body)
                )
            }
        }
    }
}

fileprivate extension Application {
    var apiServiceData: Api.ServiceData! { self.storage[Api.ServiceData.self] }
}
