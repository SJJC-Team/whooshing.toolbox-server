import Vapor
import Fluent
import FluentPostgresDriver
import ErrorHandle
import WhooshingClient
import Cryptos
import FileStorage
import AnyCodable
import Logging
import LoggingAdvanced
import NIOConcurrencyHelpers

public protocol ServiceType: Sendable {
    associatedtype Debuging: DebugConfig
    associatedtype Errcase: ErrList
    typealias Failure = Errcase.ErrType
    static var envPrefix: String { get }
}

public protocol DebugConfig: Sendable {
    var config: Environment.Config { get }
}

/// 描述一个 Whooshing 系统子服务，提供基本的服务控制操作
public protocol WhooshingService: Sendable {
    associatedtype Failure: Err
    associatedtype Service: ServiceType
    
    /// 底层 Vapor 应用实例
    var app: Application { get }
    /// 当前环境的配置项（端口、数据库等）
    var config: Environment.Config { get }
    /// 当前服务使用的日志记录器
    var logger: Logger { get set }
    /// 该服务所有连接的数据库
    var databases: Set<Environment.DB> { get }
    /// 调试参数
    var debugingData: Service.Debuging? { get }
    /// 异步启动应用并监听请求（会阻塞直到关闭）
    func execute() async -> Result<Void, Failure>
    /// 异步关闭 Vapor 应用
    func asyncShutdown() async -> Result<Void, Failure>
    /// 依次执行应用启动与关闭
    func executeWithAsyncShutdown() async -> Result<Void, Failure>
}

/// 通用服务启动器，封装对 Vapor 应用的初始化、配置与生命周期控制
/// 可根据不同服务类型（如 Api、Inline、Https）统一创建运行实例
///
/// 该类用于启动不同的服务模块，使用 `Whooshing.make(_)` 创建一个 Whooshing 实例
/// 并调用 `execute()` 或 `excuteWithAsyncShutdown()` 令其运行
public final class Whooshing<Service>: WhooshingService, @unchecked Sendable where Service: ServiceType {
    
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
    public struct Mode: Sendable, CustomStringConvertible, Loggerable {
        
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
        
        public var json: [String: AnyCodable] {[
            "env": AnyCodable(envrionment.name),
            "is_release": AnyCodable(envrionment.isRelease),
            "arguments": AnyCodable(envrionment.arguments)
        ]}
        
        public var description: String {
            formatJson(json)
        }
        
        public var summaryDescription: String {
            "env-\(envrionment.name)\(envrionment.isRelease ? "-release" : "")"
        }
    }
    
    /// 底层 Vapor 应用实例
    public let app: Application
    /// 当前环境的配置项（端口、数据库等）
    public let config: Environment.Config
    /// 当前服务使用的日志记录器
    public var logger: Logger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }
    
    private var _logger: Logger
    private let lock = NIOLock()
    
    /// 该服务所有连接的数据库
    public private(set) lazy var databases: Set<Environment.DB> = {
        .init(self.config.dbServices.flatMap { $0.dbs })
    }()
    
    /// 调试参数
    public let debugingData: Service.Debuging?
    
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
    
    @usableFromInline
    init(app: Application, config: Environment.Config, debugingData: Service.Debuging?, logger: Logger) {
        self.app = app
        self.config = config
        self.debugingData = debugingData
        _logger = logger
    }
}

extension Whooshing where Service == Inline {
    /// 工厂方法：构建 Inline 服务的运行实例
    /// - Parameter env: 启动环境
    @inlinable
    public static func make(_ env: Mode, logger: Logger) async -> Result<Whooshing<Service>, Failure> {
        await makeService(mode: env, logger: logger) { woo throws(Inline.Failure) in
            try await Service.config(woo)
        }
    }
}

extension Whooshing where Service == Https {
    /// 构建 Https 服务的运行实例
    /// - Parameter env: 启动环境
    @inlinable
    public static func make(_ env: Mode, logger: Logger) async -> Result<Whooshing<Service>, Failure> {
        await makeService(mode: env, logger: logger) { woo throws(Https.Failure) in
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
    public static func make(_ env: Mode, with inline: Whooshing<Inline>, logger: Logger) async -> Result<Whooshing<Service>, Failure> {
        await makeService(mode: env, logger: logger) { woo throws(Api.Failure) in
            try await Service.config(woo, inlineClient: inline.inlineClient)
        }
    }
}

extension Whooshing {
    @frozen
    public enum DirCreateAction: CustomStringConvertible, Loggerable {
        case noAction
        case createIfNeed(withIntermediateDirectories: Bool = false)
        
        public var description: String {
            switch self {
            case .noAction: "noAction"
            case .createIfNeed(let withIntermediateDirectories): "createIfNeed(withIntermediates: \(withIntermediateDirectories))"
            }
        }
    }
    
    /// 初始化一个文件加密系统(同步，若初始化失败将直接导致程序崩溃)
    ///
    /// - Parameters:
    ///     - db: 用于存储文件索引的数据库
    ///     - storagePath: 加密文件在文件系统中存储的位置，相对沙盒文件夹中的位置
    ///     - logger: 日志实例
    ///     - dirCreateAction: 创建动作，可选择自动创建根文件夹或无任何动作
    ///     - debugging: 调试状态，置为 true 则启动调试模式
    public func syncMakeFileStorage(
        for db: Environment.DB,
        storagePath: StoragePath,
        logger: Logger,
        dirCreateAction: DirCreateAction = .noAction,
        debugging: Bool = false
    ) -> FileStorage {
        asyncResultToSync {
            await self.makeFileStorage(
                for: db,
                storagePath: storagePath,
                logger: logger,
                dirCreateAction: dirCreateAction,
                debugging: debugging
            )
        }
    }
    
    /// 初始化一个文件加密系统(异步)
    ///
    /// - Parameters:
    ///     - db: 用于存储文件索引的数据库
    ///     - storagePath: 加密文件在文件系统中存储的位置，相对沙盒文件夹中的位置
    ///     - logger: 日志实例
    ///     - dirCreateAction: 创建动作，可选择自动创建根文件夹或无任何动作
    ///     - debugging: 调试状态，置为 true 则启动调试模式
    public func makeFileStorage(
        for db: Environment.DB,
        storagePath: StoragePath,
        logger: Logger,
        dirCreateAction: DirCreateAction = .noAction,
        debugging: Bool = false
    ) async -> Result<FileStorage, Failure> {
        let preLogger = logger.derive(subId: "preinit")
        
        preLogger.info("进行接入文件加密系统前置任务", metadata: [
            "storage_path": .data(storagePath),
            "dir_create_action": .data(dirCreateAction)
        ])
        
        guard let fileStorageParameter = config.fileStorage else {
            return .failure(.fileStorageInitFailed, "基本配置未提供，不支持文件加密系统")
        }
        
        preLogger.debug("任务参数", metadata: ["file_storage_parameter": .data(fileStorageParameter)])
        
        guard let key = db.parameter.fileStorageKey else {
            return .failure(.fileStorageInitFailed, "数据库未设置加密密钥，不支持文件加密系统", metadata: ["db_id": .string(db.id.string)])
        }
        
        return await .async { () throws(Failure) in
            
            let basePath = FileSystemTools.resolvePath(basePath: "/", append: fileStorageParameter.dir)
            let mainDirPath = FileSystemTools.resolvePath(basePath: basePath, append: "./\(storagePath.string)")
            
            switch dirCreateAction {
            case .noAction:
                preLogger.info("不创建目录，默认目录已存在", metadata: ["path": .string(mainDirPath)])
                break
            case .createIfNeed(withIntermediateDirectories: let c):
                let permissionAttributes = try required(throws: Errcase.fileStorageInitFailed, "权限信息读取失败", metadata: ["path": .string(mainDirPath)]) {
                    try fileStorageParameter.permission.attributes.get()
                }
                
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: mainDirPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
                    preLogger.info("目录不存在，正在创建", metadata: ["path": .string(mainDirPath)])
                    try required(throws: Errcase.fileStorageInitFailed, "主目录创建失败") {
                        try FileManager.default.createDirectory(
                            atPath: mainDirPath,
                            withIntermediateDirectories: c,
                            attributes: permissionAttributes
                        )
                    }
                } else {
                    preLogger.info("目录已存在，无需创建", metadata: ["path": .string(mainDirPath)])
                }
            }
            
            preLogger.info("接入文件加密系统前置任务完成")
            
            return try await required(throws: Errcase.fileStorageInitFailed) {
                try await FileStorage.new(
                    eventLoop: app.eventLoopGroup.next(),
                    storagePath: mainDirPath,
                    dbConfigure: debugging ? db.testingConfig : db.config,
                    masterKey: key.key,
                    logger: logger,
                    fileExtension: fileStorageParameter.fileExtension,
                    filePermission: fileStorageParameter.permission,
                    debuging: .init(tdeEncrypt: !debugging)
                ).get()
            }
        }
    }
}

extension Whooshing {
    @inlinable
    static func makeService(
        mode: Mode,
        logger: Logger,
        config conf: (Whooshing<Service>) async throws(Service.Failure) -> ()
    ) async -> Result<Whooshing<Service>, Failure> {
        await .async { () throws(Failure) in
            let initLogger = logger.derive(subId: "sysinit")
            
            initLogger.info("正在初始化 Whooshing 服务", metadata: ["mode": .summaryData(mode)])
            initLogger.debug("详细参数", metadata: ["mode": .data(mode)])
            
            let config: Environment.Config
            
            var env = mode.envrionment
            
            // 修复 Vapor 在 swift test 下会错误解析 SPM 注入的参数（如 --test-bundle-path 等）
            // 如果是在 testing 环境，或是检测到有 xctest 相关的参数，直接清理参数
            if env == .testing || env.arguments.contains(where: { $0.contains("xctest") || $0.hasPrefix("--test") }) {
                env.arguments = ["vapor"]
            }
            
            if ![Environment.production, .development, .testing].contains(env) {
                fatalError("环境变量 \(env.name) 无法识别")
            }
            
            var debugPara: Service.Debuging? = nil
            if let dp = mode.debuging {
                if [Environment.development, .testing].contains(env) {
                    initLogger.info("启动无依赖独立运行模式")
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
            
            initLogger.debug("准备 Vapor 实例")

            let app = try await required(throws: Self.Errcase.vaporAppCreateFailed) {
                try await Application.make(env)
            }
            app.logger = logger.derive(subId: "vapor")
            app.http.server.configuration.hostname = config.hostname
            app.http.server.configuration.port = config.port
            
            initLogger.debug("准备数据库实例")
            
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
            let service = Self(app: app, config: config, debugingData: debugPara, logger: logger)
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
