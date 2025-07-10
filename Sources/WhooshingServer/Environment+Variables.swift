import FluentPostgresDriver
import Vapor
import Cryptos
import FileStorage

public extension Environment {
    /// 代表服务模块当前环境的配置项，例如服务端口、数据库信息、域名等。
    @frozen
    struct Config: Sendable {
        /// 在 configure.yaml 中设置的服务名称
        public let name: String
        /// 当前服务监听的端口号
        public let port: Int
        /// 当前服务的监听地址
        public let hostname: String
        /// 所配置的数据库列表，仅支持 PostgreSQL 数据库
        public let dbServices: [DBService]
        /// 服务管理平台的基础 URL，用于内部通信
        public let managerUrl: URL
        /// 可选的域名信息
        public let domain: String?
        /// 文件存储的主存储目录
        public let fileStorageDir: String?
        
        @inlinable
        public init() { self = Self(name: "Testing") }
        
        /// 初始化环境配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
        /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
        /// - Parameters:
        ///   - name: 环境名称
        ///   - hostname: 服务监听地址
        ///   - port: 服务监听端口
        ///   - dbServices: 数据库服务列表
        ///   - managerUrl: 模块管理器的 URL 链接
        ///   - domain: 可选域名信息
        ///   - fileStorageDir: 文件存储的主存储目录，指定为 nil 表示不支持文件存储
        @inlinable
        public init(
            name: String,
            port: Int = 6500,
            hostname: String = "127.0.0.1",
            dbServices: [DBService] = [],
            managerUrl: URL = .init(string: "http://testing.com")!,
            domain: String? = nil,
            fileStorageDir: String? = nil
        ) {
            self.name = name
            self.fileStorageDir = fileStorageDir
            self.port = port
            self.hostname = hostname
            self.dbServices = dbServices
            self.managerUrl = managerUrl
            self.domain = domain
        }
    }
    
    /// 表示一个数据库连接的配置项，仅支持 PostgreSQL 数据库
    @frozen
    struct DBService: Sendable {
        /// 数据库名称
        public let id: DatabaseID
        /// 数据库监听端口号
        public let port: Int
        /// 该数据库服务中的所有数据库名称
        public let dbs: [DB]
        
        @inlinable
        public init() { self = Self(name: "postgres") }
        
        /// 初始化数据库配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
        /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
        /// - Parameters:
        ///   - name: 数据库服务的名称
        ///   - databases: 该数据库服务中的所有数据库列表
        ///   - port: 监听端口
        ///   - dbParameters: 该数据库服务中的数据库的配置列表
        public init(
            name: String,
            port: Int = 5432,
            dbParameters: [DB.Parameter] = []
        ) {
            let id = DatabaseID(string: name)
            self.id = id
            self.port = port
            self.dbs = dbParameters.map { parameter in
                DB(dbServiceId: id, port: port, parameter: parameter)
            }
        }
    }
    
    @frozen
    struct DB: Sendable {

        @frozen
        public struct Parameter: Sendable {
            /// 该数据库的名称
            public let name: String
            /// 用于连接数据库的用户名
            public let user: String
            /// 用于连接数据库的主机名，只有测试时会使用。
            /// PostgreSQL 生产环境仅允许运行在本地
            public let unsafeTestOnlyHost: String?
            /// 数据库访问密码（内部使用）
            /// 内部存储，不允许外界访问
            internal let password: String
            /// 文件存储系统的加密密钥
            /// 内部存储，不允许外界访问
            internal let fileStorageKey: Crypto.Symm.Key
            
            /// 初始化数据库配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
            /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
            /// - Parameters:
            ///   - name: 数据库服务的名称
            ///   - user: 连接用户名
            ///   - password: 连接密码
            ///   - unsafeTestOnlyHost: 用于连接数据库的主机名，只有测试时会使用。
            ///   - fileStorageKey: 文件存储系统的加密密钥
            public init(
                name: String,
                user: String = "postgres",
                password: String = "password",
                unsafeTestOnlyHost: String? = nil,
                fileStorageKey: Crypto.Symm.Key = Crypto.Symm.makeKey(),
            ) {
                self.name = name
                self.user = user
                self.password = password
                self.unsafeTestOnlyHost = unsafeTestOnlyHost
                self.fileStorageKey = fileStorageKey
            }
        }
        
        /// 该数据库所属数据库服务的 id
        public let dbServiceId: DatabaseID
        /// 用于 Fluent 识别的数据库标识符
        public let id: DatabaseID
        /// 数据库监听端口号
        public let port: Int
        /// 该数据库的参数配置
        public let parameter: Parameter
        
        @usableFromInline
        init() { self = Self(dbServiceId: .init(string: "postgres"), port: 5432, parameter: .init(name: "postgres")) }
        
        @usableFromInline
        internal init(
            dbServiceId: DatabaseID,
            port: Int = 5432,
            parameter: Parameter
        ) {
            self.dbServiceId = dbServiceId
            self.id = DatabaseID(string: "\(dbServiceId)/\(parameter.name)")
            self.port = port
            self.parameter = parameter
        }
        
        /// 返回当前数据库的实际连接配置对象
        /// 仅仅在测试时使用
        public var testingConfig: SQLPostgresConfiguration {
            .init(
                hostname: parameter.unsafeTestOnlyHost != nil ? parameter.unsafeTestOnlyHost! : "localhost",
                port: port,
                username: parameter.user,
                password: parameter.password,
                database: parameter.name,
                tls: .disable
            )
        }
        
        @usableFromInline
        var config: SQLPostgresConfiguration {
            .init(
                hostname: "localhost",
                port: port,
                username: parameter.user,
                password: parameter.password,
                database: parameter.name,
                tls: .disable
            )
        }
    }
}
