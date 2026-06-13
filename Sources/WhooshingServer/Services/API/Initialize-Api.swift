import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging
import WhooshingClient

public enum Api: ServiceType {
    
    @inlinable
    public static var name: String { "api" }
    
    /// 记录用户的认证信息，用于之后的认证验证机制
    @frozen
    public struct AuthExchangeData: Content {
        /// 用户凭据
        public let credential: Data
        /// 加密后的用户口令
        public let tokenEncrypted: Data
    }
    
    /// 用于在无依赖 debug (Whooshing.Env.independentDebug) 模式下运行的依赖参数
    ///
    /// 伪造该模块所必须的认证机制，服务配置以无依赖运行
    ///
    /// > 在一般的 .production 或 .debug 模式下，
    /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
    /// 而在独立无依赖运行模式下，需要手动提供
    @frozen
    public struct Debuging: DebugConfig, Sendable {
        
        public typealias UserToken = SendableSymmKey
        public typealias Auth = @Sendable (AuthExchangeData) throws -> UserToken
        /// 用户身份认证的机制回调函数
        ///
        /// 每次用户连线将会提供用户凭据 (``credential``) 和加密过的用户密钥 (``tokenEncrypted``)
        /// 你可以自定这些是否合法，选择抛出错误(拒绝连线)或将该用户的密钥作为返回值(认证成功)
        ///
        /// 使用 `testingTokenAuth(with:encrypted:)`
        /// 方法验证一个加密过后的用户密钥(encrypted)是否是由原密钥(origin)加密得来的
        /// 如果是，则返回该用户密钥。若不是，会抛出错误
        ///
        /// ``` swift
        /// // 你可以生成一些用户的密钥，为 256 bit(64 bytes) 数据的 base64 编码的字符串，以进行后续的判断
        /// let validUserTokens = [
        ///     "hW0p4sB0ECDoZ2KNq/TwYtc5WRidh/6f11O//eQdt7I=",
        ///     "I/N/ByjfgOeGKsbKKM3GMLQnJgnj+l8Kg5rhENBbi3g=",
        ///     ...
        /// ]
        ///
        /// // 创建无依赖运行参数
        /// let debugging = API.Debugging(config: .init()) { auth in
        ///     let credential = auth.credential
        ///     let tokenEncrypted = auth.tokenEncrypted
        ///     // 遍历用户密钥列表，依次对比 tokenEncrypted 是否合法
        ///     for origin in validUserTokens {
        ///         if let key = try? Self.testingTokenAuth(with: origin, encrypted: tokenEncrypted) {
        ///             // 该 key 为该用户的密钥 key 原文，直接返回，表示该用户的用户身份合法，接受连线
        ///             return key
        ///         }
        ///     }
        ///     // 没有任何一个 key 通过了比对，则抛出错误，表示该用户身份不合法，拒绝连线
        ///     // 当然，你可以抛出任何错误
        ///     throw Abort(.badRequest, reason: "用户口令不正确")
        /// }
        /// ```
        public let auth: Auth
        
        /// 服务配置，原来通过 Whooshing 系统环境变量自动获取
        ///
        /// 指定诸如监听地址，PostgreSQL 数据库的连线参数，等等
        /// 见 ``Environment.Config``
        public let config: Environment.Config
        
        /// 提供参数初始化 Api 依赖参数
        ///
        /// - Parameters:
        ///   - config: 用户身份认证的机制回调函数
        ///   - auth: 用户身份认证的机制回调函数
        /// - Returns:
        ///   初始化的 Api 依赖参数
        @inlinable
        public init(
            config: Environment.Config,
            auth: @escaping Auth
        ) {
            self.config = config
            self.auth = auth
        }
        
        /// 验证一个加密过后的用户密钥(encrypted)是否是由原密钥(origin)加密得来的
        ///
        /// - Parameters
        ///   - origin: 原用户密钥，为 256 bit(64 bytes) 数据的 base64 编码的字符串
        ///   - encrypted: 加密后的用户密钥
        /// - Returns
        ///   若 encrypted 确为 origin 加密得到的，则返回原用户密钥
        /// - Throws
        ///   若 encrypted 并非为 origin 加密得到的，则抛出错误 "用户口令不正确"
        @inlinable
        public static func testingTokenAuth(with origin: String, encrypted: Data) throws -> SendableSymmKey {
            let keyData = try Base64String(origin).dataRes.get()
            let key = SendableSymmKey(key: .init(data: keyData))
            let authData: Data = try Crypto.Symm.decrypt(encrypted, key: key.key).get()
            guard keyData == authData else { throw Abort(.badRequest, reason: "用户口令不正确") }
            return key
        }
    }
    
    /// 配置 API 服务模块
    @usableFromInline
    internal static func config(
        _ woo: Whooshing<Api>,
        inlineClient: AnyWhooshingClient<InlineClientErrcase>,
        driverKeys: [any Environment.DriverKey.Type]
    ) async throws(Failure) {
        woo.app.http.server.configuration.serviceName = "API"
        woo.app.logger.debug("从环境变量中取得该服务模块的参数")
        
        let authenticationURL: URL
        let debugAuth: Debuging.Auth?
        if let debug = woo.debugingData {
            authenticationURL = .init(string: "http://testing.com")!
            debugAuth = debug.auth
        } else {
            authenticationURL = try required(throws: Errcase.initFailed, "环境变量解析失败") {
                try ServicePara.parse(prefix: "WHOOSHING_API_SERVICE_PRIVATE", driverKeys: driverKeys).authenticationURL
            }
            debugAuth = nil
        }
        
        woo.app.logger.debug("注册 HTTP IO 加密模块")
        woo.app.use(httpIOHandler: .init(HttpIOCrypto(app: woo)))
        woo.app.logger.debug("注册客户端身份验证中间件")
        woo.app.middleware.use(GuardMiddleware(authenticationURL: authenticationURL, debugingAuth: debugAuth))
        woo.app.logger.debug("初始化服务数据")
        woo.app.storage[ServiceData.self] = .init(inlineClient: inlineClient)
    }
}
