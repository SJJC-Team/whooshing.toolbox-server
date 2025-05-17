import FluentPostgresDriver
import Vapor

public extension Environment {
    /// 代表服务模块当前环境的配置项，例如服务端口、数据库信息、域名等。
    struct Config: Sendable {
        /// 当前环境名称，如 "Production"、"Debug"
        public let name: String
        /// 当前服务监听的端口号
        public let port: Int
        /// 所配置的数据库列表，仅支持 PostgreSQL 数据库
        public let databases: [DB]
        /// 服务管理平台的基础 URL，用于内部通信
        public let managerUrl: URL
        /// 可选的域名信息
        public let domain: String?
        
        public init() { self = Self(name: "Testing") }
        
        /// 初始化环境配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
        /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
        /// - Parameters:
        ///   - name: 环境名称
        ///   - port: 服务监听端口
        ///   - databases: 数据库列表
        ///   - managerUrl: 服务管理平台 URL
        ///   - domain: 可选域名信息
        public init(
            name: String,
            port: Int = 6500,
            databases: [DB] = [],
            managerUrl: URL = .init(string: "http://testing.com")!,
            domain: String? = nil
        ) {
            self.name = name
            self.port = port
            self.databases = databases
            self.managerUrl = managerUrl
            self.domain = domain
        }
    }
    
    /// 表示一个数据库连接的配置项，仅支持 PostgreSQL 数据库
    struct DB: Sendable {
        /// 数据库名称
        public let name: String
        /// 数据库监听端口号
        public let port: Int
        /// 用于连接数据库的用户名
        public let user: String
        /// 数据库访问密码（内部使用）
        internal let password: String
        /// 每个事件循环最大连接数
        public let maxConnectionsPerEventLoop: Int
        /// 连接池获取连接的最大等待时间
        public let connectionPoolTimeout: TimeAmount
        /// 数据库日志级别（如 info、debug）
        public let sqlLogLevel: Logger.Level
        
        public init() { self = Self(name: "postgres") }
        
        /// 初始化数据库配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
        /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
        /// - Parameters:
        ///   - name: 数据库名称
        ///   - port: 监听端口
        ///   - user: 连接用户名
        ///   - password: 连接密码
        ///   - maxConnectionsPerEventLoop: 每个事件循环最大连接数
        ///   - connectionPoolTimeout: 连接池超时时间
        ///   - sqlLogLevel: 日志级别
        public init(
            name: String,
            port: Int = 5432,
            user: String = "postgres",
            password: String = "password",
            maxConnectionsPerEventLoop: Int = 1,
            connectionPoolTimeout: TimeAmount = .seconds(10),
            sqlLogLevel: Logger.Level = .info
        ) {
            self.name = name
            self.port = port
            self.user = user
            self.password = password
            self.maxConnectionsPerEventLoop = maxConnectionsPerEventLoop
            self.connectionPoolTimeout = connectionPoolTimeout
            self.sqlLogLevel = sqlLogLevel
        }
        
        /// 当前数据库标识符（基于名称）
        public var id: DatabaseID { .init(string: name) }
        
        /// 返回当前数据库的实际连接配置对象
        public var config: DatabaseConfigurationFactory {
            .postgres(configuration: .init(
                hostname: "localhost",
                port: port,
                username: user,
                password: password,
                database: name,
                tls: .disable
            ),
            maxConnectionsPerEventLoop: maxConnectionsPerEventLoop,
            connectionPoolTimeout: connectionPoolTimeout,
            sqlLogLevel: sqlLogLevel)
        }
    }
}
