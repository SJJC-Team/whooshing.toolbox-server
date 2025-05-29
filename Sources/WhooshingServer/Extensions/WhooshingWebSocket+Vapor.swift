import WhooshingClient
import WhooshingWebSocket
import Logging
import Vapor

public extension ApiWebSocket {
    /// Vapor 环境下的初始化方式。
    /// 自动从 Request 获取 eventLoop 和 logger。
    /// - Parameters:
    ///   - credential: 身份凭证。
    ///   - token: 授权令牌。
    ///   - request: Vapor Request 上下文。
    convenience init(credential: String, token: String, request: Request) {
        self.init(credential: credential, token: token, eventLoop: request.eventLoop, logger: request.logger)
    }

}

public extension HttpsWebSocket {
    /// Vapor 环境下的初始化方式。
    /// 自动从 Request 获取 eventLoop 和 logger。
    /// - Parameters:
    ///   - request: Vapor Request 上下文。
    convenience init(request: Request) {
        self.init(in: request.eventLoop, logger: request.logger)
    }
}
