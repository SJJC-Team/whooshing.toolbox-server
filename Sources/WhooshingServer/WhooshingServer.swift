import Vapor
import Fluent
import FluentPostgresDriver
import ErrorHandle
import WhooshingClient
import Cryptos

public protocol ServiceType {
    associatedtype Debuging: DebugConfig
    static var envPrefix: String { get }
}

public protocol DebugConfig {
    var config: Environment.Config { get }
}

/// 通用服务启动器，封装对 Vapor 应用的初始化、配置与生命周期控制
/// 可根据不同服务类型（如 API、Inline、Https）统一创建运行实例
///
/// 该类用于启动不同的服务模块，使用 `Whooshing.make(_)` 创建一个 Whooshing 实例
/// 并调用 `execute()` 或 `excuteWithAsyncShutdown()` 令其运行
public final class Whooshing<Service>: @unchecked Sendable where Service: ServiceType {
    /// 启动环境枚举，表示当前服务运行的目标环境
    ///
    /// 可以指定运行模式为 production, debug, independentDebug
    ///
    /// 其中，independentDebug 表示不依赖任何外部模块，比如用户身份认证模块，服务管理模块等等
    /// 自动内部处理这些认证请求，保证可无依赖运行在本机。
    /// 而这需要提供一些服务参数，不同的服务需要不同的参数，见
    ///
    /// - ``API.Debuging``
    /// - ``Inline.Debuging``
    /// - ``Https.Debuging``
    ///
    /// - Warning: independentDebug 模式应当永远仅仅用作测试，请勿在生产环境使用
    public enum Env {
        /// 生产环境，使用正式配置
        case production
        /// 调试环境，使用 development 配置
        case debug
        /// 独立调试配置，传入调试参数结构体
        /// > 在一般的 .production 或 .debug 模式下，
        /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
        /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
        /// - Warning: 该模式应当永远仅仅用作测试，请勿在生产环境使用
        case independentDebug(Service.Debuging)
    }
    
    /// 底层 Vapor 应用实例
    public let app: Application
    /// 当前环境的配置项（端口、数据库等）
    public let config: Environment.Config
    /// 当前服务使用的日志记录器
    public var logger: Logger { self.app.logger }
    
    internal let debugingData: Service.Debuging?
    
    /// 异步启动应用并监听请求（会阻塞直到关闭）
    public func execute() async throws { try await app.execute() }
    /// 异步关闭 Vapor 应用
    public func asyncShutdown() async throws { try await app.asyncShutdown() }
    /// 依次执行应用启动与关闭
    public func executeWithAsyncShutdown() async throws {
        try await app.execute()
        try await app.asyncShutdown()
    }
    
    private init(app: Application, config: Environment.Config, debugingData: Service.Debuging?) {
        self.app = app
        self.config = config
        self.debugingData = debugingData
    }
}

extension Whooshing where Service == Inline {
    /// 工厂方法：构建 Inline 服务的运行实例
    /// - Parameter env: 启动环境
    public static func make(_ env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0)
        }
    }
}

extension Whooshing where Service == Https {
    /// 构建 Https 服务的运行实例
    /// - Parameter env: 启动环境
    public static func make(_ env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0)
        }
    }
}

extension Whooshing where Service == API {
    /// 构建 API 服务运行实例，并注入 Inline 客户端作为依赖
    ///
    /// API 服务依赖于 Inline 服务，因此请保证先创建 Inline 模块
    /// 后创建 API 模块，并将 Inline 模块作为参数传入
    ///
    /// - Parameters:
    ///   - env: 启动环境
    ///   - inline: 预先构建的 Inline 服务
    public static func make(_ env: Env, with inline: Whooshing<Inline>) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0, inlineClient: inline.inlineClient)
        }
    }
}

private extension Whooshing {
    static func makeService(environment: Env, config conf: (Self) async throws -> ()) async throws -> Self {
        let env: Environment
        let debuggingData: Service.Debuging?
        let config: Environment.Config
        
        switch environment {
        case .production:
            env = .production
            debuggingData = nil
            config = try Environment.get(with: Service.envPrefix)
        case .debug:
            env = .development
            debuggingData = nil
            config = try Environment.get(with: Service.envPrefix)
        case .independentDebug(let debugPara):
            env = .development
            debuggingData = debugPara
            config = debugPara.config
        }
        
        let app = try await Application.make(env)
        app.http.server.configuration.port = config.port
        for db in config.databases { app.databases.use(db.config, as: db.id) }
        let service = Self(app: app, config: config, debugingData: debuggingData)
        try await conf(service)
        return service
    }
}
