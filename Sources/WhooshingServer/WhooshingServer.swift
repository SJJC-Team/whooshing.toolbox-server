import Vapor
import Fluent
import FluentPostgresDriver
import ErrorHandle
import WhooshingClient
import Cryptos
import FileStorage

public protocol ServiceType {
    associatedtype Debuging: DebugConfig
    associatedtype Errcase: ErrList
    typealias Failure = Errcase.ErrType
    static var envPrefix: String { get }
}

public protocol DebugConfig: Sendable {
    var config: Environment.Config { get }
}

/// 通用服务启动器，封装对 Vapor 应用的初始化、配置与生命周期控制
/// 可根据不同服务类型（如 Api、Inline、Https）统一创建运行实例
///
/// 该类用于启动不同的服务模块，使用 `Whooshing.make(_)` 创建一个 Whooshing 实例
/// 并调用 `execute()` 或 `excuteWithAsyncShutdown()` 令其运行
public final class Whooshing<Service>: @unchecked Sendable where Service: ServiceType {
    
    public typealias Failure = Errcase.ErrType
    
    /// 启动模式枚举，表示当前服务运行的目标环境
    ///
    /// 可以指定运行模式为 production, debug, independentDebug
    ///
    /// Mode.detect 表示自动从环境变量检测运行模式
    ///
    /// 其中，independentDebug 表示不依赖任何外部模块，比如用户身份认证模块，服务管理模块等等
    /// 自动内部处理这些认证请求，保证可无依赖运行在本机。
    /// 而这需要提供一些服务参数，不同的服务需要不同的参数，见
    ///
    /// - ``Api.Debuging``
    /// - ``Inline.Debuging``
    /// - ``Https.Debuging``
    ///
    /// - Warning: independentDebug 模式应当永远仅仅用作测试，请勿在生产环境使用
    @frozen
    public struct Mode: Sendable {
        
        /// 生产环境，使用正式配置
        @inlinable public static var production: Mode { Mode(envrionment: .production) }
        
        /// 调试环境，使用 development 配置
        @inlinable public static var debug: Mode { Mode(envrionment: .development) }
        
        /// 独立调试配置，传入调试参数结构体
        /// > 在一般的 .production 或 .debug 模式下，
        /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
        /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
        /// - Warning: 该模式应当永远仅仅用作测试，请勿在生产环境使用
        @inlinable public static func independentDebug(_ debuging: Service.Debuging) -> Mode { Mode(envrionment: .development, debuging: debuging) }
        
        /// 测试配置，传入调试参数结构体应当仅仅用在单元测试中
        /// > 在一般的 .production 或 .debug 模式下，
        /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
        /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
        /// - Warning: 该模式应当永远仅仅用作测试，请勿在生产环境使用
        @inlinable public static func testing(_ debuging: Service.Debuging) -> Mode { Mode(envrionment: .testing, debuging: debuging) }
        
        /// 自动从环境变量变量判断运行模式，你需要选择提供调试参数
        /// 若你希望永远不使用 testing 或 independentDebug 模式，可以指定为 nil
        /// 这样若环境中出现了这两个模式，将会直接触发 fatalError
        ///
        /// Mode.production 对应 --env production
        /// Mode.debug 与 Mode.independentDebug 对应 --env development
        /// Mode.testing 对应 --env testing
        ///
        /// > 在一般的 .production 或 .debug 模式下，
        /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
        /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
        @inlinable public static func detect(_ debuging: Service.Debuging? = nil) -> Mode {
            let env = try! Environment.detect()
            return Mode(envrionment: env, debuging: debuging)
        }
        
        /// 当前运行的环境
        public var envrionment: Environment
        
        @usableFromInline
        let debuging: Service.Debuging?
        
        @inlinable init(envrionment: Environment, debuging: Service.Debuging? = nil) {
            self.envrionment = envrionment
            self.debuging = debuging
        }
    }
    
    /// 底层 Vapor 应用实例
    public let app: Application
    /// 当前环境的配置项（端口、数据库等）
    public let config: Environment.Config
    /// 当前服务使用的日志记录器
    public var logger: Logger { self.app.logger }
    
    @usableFromInline
    let debugingData: Service.Debuging?
    
    /// 异步启动应用并监听请求（会阻塞直到关闭）
    @inlinable
    public func execute() async -> Result<Void, Failure> {
        await .async(throws: Errcase.executionFailed) {
            try await app.execute()
        }
    }
    /// 异步关闭 Vapor 应用
    @inlinable
    public func asyncShutdown() async -> Result<Void, Failure> {
        await .async(throws: Errcase.shutdownFailed) {
            try await app.asyncShutdown()
        }
    }
    /// 依次执行应用启动与关闭
    @inlinable
    public func executeWithAsyncShutdown() async -> Result<Void, Failure> {
        await .async { () throws(Failure) in
            try await execute().get()
            try await asyncShutdown().get()
        }
    }
    
    @inlinable
    init(app: Application, config: Environment.Config, debugingData: Service.Debuging?) {
        self.app = app
        self.config = config
        self.debugingData = debugingData
    }
}

extension Whooshing where Service == Inline {
    /// 工厂方法：构建 Inline 服务的运行实例
    /// - Parameter env: 启动环境
    @inlinable
    public static func make(_ env: Mode) async -> Result<Whooshing<Service>, Failure> {
        await makeService(mode: env) { woo throws(Inline.Failure) in
            try await Service.config(woo)
        }
    }
}

extension Whooshing where Service == Https {
    /// 构建 Https 服务的运行实例
    /// - Parameter env: 启动环境
    @inlinable
    public static func make(_ env: Mode) async -> Result<Whooshing<Service>, Failure> {
        await makeService(mode: env) { woo throws(Https.Failure) in
            try await Service.config(woo)
        }
    }
}

extension Whooshing where Service == Api {
    /// 构建 API 服务运行实例，并注入 Inline 客户端作为依赖
    ///
    /// API 服务依赖于 Inline 服务，因此请保证先创建 Inline 模块
    /// 后创建 API 模块，并将 Inline 模块作为参数传入
    ///
    /// - Parameters:
    ///   - env: 启动环境
    ///   - inline: 预先构建的 Inline 服务
    @inlinable
    public static func make(_ env: Mode, with inline: Whooshing<Inline>) async -> Result<Whooshing<Service>, Failure> {
        await makeService(mode: env) { woo throws(Api.Failure) in
            try await Service.config(woo, inlineClient: inline.inlineClient)
        }
    }
}

extension Whooshing {
    public func makeFileStorage(
        for db: Environment.DB,
        storagePath: StoragePath,
        logger: Logger,
        testing: Bool = false
    ) async -> Result<FileStorage, Failure> {
        guard let fileStorageDir = config.fileStorageDir else {
            return .failure(.fileStorageInitFailed, "主目录未设置，不支持文件加密系统")
        }
        
        guard let key = db.parameter.fileStorageKey else {
            return .failure(.fileStorageInitFailed, "数据库 \(db.id) 未设置加密密钥，不支持文件加密系统")
        }
        
        return await FileStorage.new(
            eventLoop: app.eventLoopGroup.next(),
            storagePath: FileSystemTools.resolvePath(basePath: fileStorageDir, append: storagePath.string),
            dbConfigure: testing ? db.testingConfig : db.config,
            masterKey: key,
            logger: logger
        ).mapError(as: Errcase.fileStorageInitFailed)
    }
}

extension Whooshing {
    @inlinable
    static func makeService(
        mode: Mode,
        config conf: (Whooshing<Service>) async throws(Service.Failure) -> ()
    ) async -> Result<Whooshing<Service>, Failure> {
        await .async { () throws(Failure) in
            let config: Environment.Config
            
            let env = mode.envrionment
            
            if ![Environment.production, .development, .testing].contains(env) {
                fatalError("环境变量 \(mode.envrionment.name) 无法识别")
            }
            
            var debugPara: Service.Debuging? = nil
            if let dp = mode.debuging {
                if [Environment.development, .testing].contains(env) {
                    debugPara = dp
                    config = dp.config
                } else {
                    config = try required(throws: Self.Errcase.environmentFailed) {
                        try Environment.get(with: Service.envPrefix)
                    }
                }
            } else {
                if env == .testing {
                    fatalError("未提供调试数据，无法进入 testing 模式")
                } else {
                    config = try required(throws: Self.Errcase.environmentFailed) {
                        try Environment.get(with: Service.envPrefix)
                    }
                }
            }
            
            let app = try await required(throws: Self.Errcase.vaporAppCreateFailed) {
                try await Application.make(env)
            }
            app.http.server.configuration.hostname = config.hostname
            app.http.server.configuration.port = config.port
            if env == .testing {
                for dbService in config.dbServices {
                    for db in dbService.dbs {
                        app.databases.use(
                            .postgres(
                                configuration: db.testingConfig,
                                maxConnectionsPerEventLoop: 1,
                                connectionPoolTimeout: .seconds(10),
                                sqlLogLevel: .debug
                            ),
                            as: db.id
                        )
                    }
                }
            } else {
                for dbService in config.dbServices {
                    for db in dbService.dbs {
                        app.databases.use(
                            .postgres(
                                configuration: db.config,
                                maxConnectionsPerEventLoop: 1,
                                connectionPoolTimeout: .seconds(10),
                                sqlLogLevel: .info
                            ),
                            as: db.id
                        )
                    }
                }
            }
            let service = Self(app: app, config: config, debugingData: debugPara)
            do {
                try await conf(service)
            } catch {
                let err = Self.Errcase.serviceInitFailed.subErr(error)
                service.logger.report(error: err)
                try? await service.asyncShutdown().get()
                throw err
            }
            return service
        }
    }
}
