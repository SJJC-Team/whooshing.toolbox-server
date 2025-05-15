import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging
import WhooshingClient

public enum API: ServiceType {
    
    public static var envPrefix: String { "WHOOSHING_API_SERVICE" }
    
    public struct Debuging: DebugConfig {
        public typealias UserToken = Crypto.Symm.Key
        public typealias Auth = @Sendable (AuthExchangeData) throws -> UserToken
        public let auth: Auth
        public let config: Environment.Config
        
        public init(
            config: Environment.Config = .init(),
            auth: @escaping Auth
        ) {
            self.config = config
            self.auth = auth
        }
        
        public func testingTokenAuth(with origin: String, encrypted: Data) throws -> Crypto.Symm.Key {
            let keyData = try Base64String(origin).data()
            let key = Crypto.Symm.Key(data: keyData)
            let authData: Data = try Crypto.Symm.decrypt(encrypted, key: key)
            guard keyData == authData else { throw Abort(.badRequest, reason: "用户口令不正确") }
            return key
        }
    }
    
    public struct AuthExchangeData: Content {
        public let credential: Data
        public let tokenEncrypted: Data
    }
    
    /// 配置 API 服务模块
    internal static func config(_ woo: Whooshing<API>, inlineClient: WhooshingClient) async throws {
        woo.app.http.server.configuration.serviceName = "API"
        woo.app.logger.debug("从环境变量中取得该服务模块的参数")
        
        let authenticationURL: URL
        let debugAuth: Debuging.Auth?
        if let debug = woo.debugingData {
            authenticationURL = .init(string: "http://testing.com")!
            debugAuth = debug.auth
        } else {
            authenticationURL = try ServicePara.parse(prefix: "WHOOSHING_API_SERVICE_PRIVATE").authenticationURL
            debugAuth = nil
        }
        
        woo.app.logger.debug("注册 HTTP IO 加密模块")
        woo.app.use(httpIOHandler: HttpIOCrypto(app: woo))
        woo.app.logger.debug("注册客户端身份验证中间件")
        woo.app.middleware.use(GuardMiddleware(authenticationURL: authenticationURL, debugingAuth: debugAuth))
        woo.app.logger.debug("初始化服务数据")
        woo.app.storage[ServiceData.self] = .init(inlineClient: inlineClient)
    }
}
