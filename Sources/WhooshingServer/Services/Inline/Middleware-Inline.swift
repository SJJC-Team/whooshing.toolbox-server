import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging

/// 该文件定义了一个守护中间件，拒绝非法连接请求(例如加密算法错误导致的数据格式不正确)并解密加密请求。
/// 确保传递到之后的路由时该请求是被解密的以便处理。

extension Inline {
    
    /// 守护中间件，实现了加密访问的加密算法流程，确保后续路由可以正确解析请求
    struct GuardMiddleware: Middleware {
        
        fileprivate enum Err: String, ErrList {
            var domain: String { "woo.inline.sys.middleware.guard.err" }
            case serviceIdNotValid = "服务模块不可信，ID 验证失败"
            case keyExchangeFailed = "与服务模块通讯时密钥交换失败"
            case serviceValidateFailed = "与服务模块通讯时验证失败"
            case unknowError = "未知错误"
        }
        
        func respond(to req: Request, chainingTo next: any Responder) -> NIOCore.EventLoopFuture<Response> {
            guard let channel = req.channel else { return req.eventLoop.makeFailedFuture(Err.unknowError.d("未找到 Channel", 10013, (#file, #line))) }
            let id = ObjectIdentifier(channel)
            if req.application.inlineServiceData.connectionValidate[id] == true {
                req.logger.debug("Inline.Server-处理已认证客户端的真正请求: \(channel.serverAddrInfo)")
                return next.respond(to: req)
            } else {
                if let _ = req.application.inlineServiceData.connectionKeys[id] {
                    req.logger.debug("Inline.Server-验证客户端的服务: \(channel.serverAddrInfo)")
                    return validateService(req: req, id: id)
                } else {
                    req.logger.debug("Inline.Server-与客户端交换密钥: \(channel.serverAddrInfo)")
                    return keyExchange(req: req, id: id)
                }
            }
        }

        struct JSONData: Content {
            let data: Data
        }
        
        // 进行密钥交换
        @Sendable private func keyExchange(req: Request, id: ObjectIdentifier) -> EventLoopFuture<Response> {
            do {
                req.logger.trace("Inline.Server-与客户端密钥交换: 收到对方的公钥")
                let pubKey = try Crypto.Asym.CPublicKey(data: req.content.decode(JSONData.self).data)
                req.logger.trace("Inline.Server-与客户端密钥交换: 创建自己的密钥对")
                let keyPair = Crypto.Asym.makeCryptoKeyPair()
                req.logger.trace("Inline.Server-与客户端密钥交换: 计算共享密钥")
                let sharedKey = try Crypto.Asym.keyEncapsulate(key: keyPair.private, partyPublic: pubKey, salt: Crypto.hash("inline.shared.key"), info: "")
                req.logger.trace("Inline.Server-与客户端密钥交换: 将 sharedKey 记录在 connectionKeys 中，却把 validate 设置为 nil，表示下次请求时需要进行 Validate，而无需再交换密钥")
                req.application.inlineServiceData.connectionKeys[id] = sharedKey
                req.application.inlineServiceData.connectionValidate[id] = nil
                req.logger.trace("Inline.Server-与客户端密钥交换: 发送自己的公钥")
                return req.eventLoop.makeSucceededFuture(Response(status: .ok, body: .init(data: keyPair.public.data())))
            } catch let err {
                return req.eventLoop.makeFailedFuture(Err.keyExchangeFailed.d(10012, #file, #line).subErr(err))
            }
        }

        // 进行服务验证，确认对方的服务 ID 是可信的
        @Sendable private func validateService(req: Request, id: ObjectIdentifier) -> EventLoopFuture<Response> {
            do {
                req.application.inlineServiceData.connectionValidate[id] = false
                req.logger.trace("Inline.Server-与客户端服务验证: 取得对方的服务 ID")
                let serviceId = try UUID(data: req.content.decode(JSONData.self).data)
                req.logger.trace("Inline.Server-与客户端服务验证: 判断该 ID 是否可信")
                let res = req.application.inlineServiceData.moduleDatas.contains { $0.serviceId == serviceId }
                guard res == true else { throw Err.serviceIdNotValid.d(10011, #file, #line) }
                req.logger.trace("Inline.Server-与客户端服务验证: 设置标志位")
                req.application.inlineServiceData.connectionValidate[id] = true
                req.logger.trace("Inline.Server-与客户端服务验证: 发送回执，表示验证成功")
                return req.eventLoop.makeSucceededFuture(.init(status: .ok, body: .init(data: "authorized".data(using: .utf8)!)))
            } catch let err {
                return req.eventLoop.makeFailedFuture(Err.serviceValidateFailed.d(10013, #file, #line).subErr(err))
            }
        }
    }
}
