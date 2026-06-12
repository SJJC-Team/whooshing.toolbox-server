import FluentPostgresDriver
import Vapor
import Cryptos
import AnyCodable
import LoggingAdvanced
import OrderedCollections
import NIOConcurrencyHelpers

public extension Environment {
    /// 代表服务模块当前环境的配置项，例如服务端口、数据库信息、域名等。
    @frozen
    struct Config: @unchecked Sendable, CustomStringConvertible, Loggerable {
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
        /// 日志文件保存的路径，多个路径将会同时输出多个日志文件
        /// 日志文件提供 Rotating 功能，单个文件过大将输出至新文件中且备份旧日志
        public let logFileUrls: [URL]
        
        /// 存储所有的 storage key，可用于遍历 storage 的内容
        public let driverKeys: [any DriverKey.Type]
        /// 提供额外的 storage，用于存储扩展参数
        public var storage: Storage {
            get { lock.withLock { __storage } }
            set { lock.withLock { __storage = newValue } }
        }
        
        private let lock = NIOLock()
        private var __storage = Storage()
        
        /// 永远不应直接调用该初始化函数
        @inlinable
        public init() { self.init(name: "Testing") }
        
        /// 初始化环境配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
        /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
        /// - Parameters:
        ///   - name: 环境名称
        ///   - hostname: 服务监听地址
        ///   - port: 服务监听端口
        ///   - dbServices: 数据库服务列表
        ///   - managerUrl: 模块管理器的 URL 链接
        ///   - domain: 可选域名信息
        ///   - fileStorageParameter: 文件存储系统的基本配置参数，为 nil 表示不支持文件加密系统
        public init(
            name: String,
            port: Int = 6500,
            hostname: String = "127.0.0.1",
            dbServices: [DBService] = [],
            managerUrl: URL = .init(string: "http://testing.com")!,
            domain: String? = nil,
            driverKeys: [any DriverKey.Type] = [],
            logFileUrls: [URL] = []
        ) {
            self.name = name
            self.port = port
            self.hostname = hostname
            self.dbServices = dbServices
            self.managerUrl = managerUrl
            self.domain = domain
            self.driverKeys = driverKeys
            self.logFileUrls = logFileUrls
        }
        
        @inlinable
        public var json: [String: AnyCodable] {
            var paras: [String: AnyCodable] = [:]
            for key in driverKeys {
                paras[key.label] = AnyCodable(storage[key])
            }
            
            return [
                "name": AnyCodable(name),
                "port": AnyCodable(port),
                "hostname": AnyCodable(hostname),
                "db_services": AnyCodable(dbServices.map { $0.json }),
                "manager_url": AnyCodable(managerUrl),
                "domain": AnyCodable(domain),
                "storage": AnyCodable(paras)
            ]
        }
        
        @inlinable
        public var description: String {
            formatJson(json)
        }
    }
    
    /// 一个数据库服务连接的配置项，仅支持 PostgreSQL 数据库，一个数据库服务中可有多个数据库
    @frozen
    struct DBService: Hashable, Sendable, CustomStringConvertible, Loggerable {
        /// 数据库名称
        public let id: DatabaseID
        /// 数据库监听端口号
        public let port: Int
        /// 该数据库服务中的所有数据库名称
        public let dbs: [DB]
        
        /// 永远不应直接调用该初始化函数
        @inlinable
        public init() { self = Self(name: "postgres") }
        
        /// 初始化数据库配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
        /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
        /// - Parameters:
        ///   - name: 数据库服务的名称
        ///   - databases: 该数据库服务中的所有数据库列表
        ///   - port: 监听端口
        ///   - dbParameters: 该数据库服务中的数据库的配置列表
        @inlinable
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
        
        @inlinable
        public var json: [String: AnyCodable] {[
            "id": AnyCodable(id),
            "port": AnyCodable(port),
            "dbs": AnyCodable(dbs.map { $0.json })
        ]}
        
        @inlinable
        public var description: String {
            formatJson(json)
        }
    }
    
    /// 一个数据库的配置项，仅支持 PostgreSQL 数据库
    @frozen
    struct DB: Hashable, Sendable, CustomStringConvertible, Loggerable {
        /// 该数据库所属数据库服务的 id
        public let dbServiceId: DatabaseID
        /// 用于 Fluent 识别的数据库标识符
        public let id: DatabaseID
        /// 数据库监听端口号
        public let port: Int
        /// 该数据库的参数配置
        public let parameter: Parameter
        
        @frozen
        public struct Parameter: Hashable, Sendable, CustomStringConvertible, Loggerable {
            /// 该数据库的名称
            public let name: String
            /// 用于连接数据库的用户名
            public let user: String
            /// 用于连接数据库的主机名，只有测试时会使用。
            /// PostgreSQL 生产环境仅允许运行在本地
            public let testingHost: String?
            /// 文件存储系统的加密密钥，为 nil 表示不支持文件加密系统
            public let fileStorageKey: SendableSymmKey?
            /// 数据库访问密码（内部使用）
            /// 内部存储，不允许外界访问
            internal let password: String
            
            /// 初始化数据库配置，仅在 ``Whooshing.Env`` 为 `.independentDebug(...)` 时才可能使用
            /// 这些参数在非 `.independentDebug(...)` 模式下会自动从环境变量中读取
            /// - Parameters:
            ///   - name: 数据库服务的名称
            ///   - user: 连接用户名
            ///   - password: 连接密码
            ///   - testingHost: 用于连接数据库的主机名，只有测试时会使用。
            ///   - fileStorageKey: 文件存储系统的加密密钥，为 nil 表示不支持文件加密系统
            public init(
                name: String,
                user: String = "postgres",
                password: String = "password",
                testingHost: String? = nil,
                fileStorageKey: SendableSymmKey? = nil
            ) {
                self.name = name
                self.user = user
                self.password = password
                self.testingHost = testingHost
                self.fileStorageKey = fileStorageKey
            }
            
            @inlinable
            public var json: [String: AnyCodable] {[
                "name": AnyCodable(name),
                "user": AnyCodable(user),
                "testing_host": AnyCodable(testingHost)
            ]}
            
            @inlinable
            public var description: String {
                formatJson(json)
            }
        }
        
        /// 永远不应直接调用该初始化函数
        @inlinable
        public init() { self = Self(dbServiceId: .init(string: "postgres"), port: 5432, parameter: .init(name: "postgres")) }
        
        @usableFromInline
        internal init(
            dbServiceId: DatabaseID,
            port: Int = 5432,
            parameter: Parameter
        ) {
            self.dbServiceId = dbServiceId
            self.id = DatabaseID(string: "\(dbServiceId.string)/\(parameter.name)")
            self.port = port
            self.parameter = parameter
        }
        
        /// 返回当前数据库的实际连接配置对象
        /// 仅仅在测试时使用
        public var testingConfig: SQLPostgresConfiguration {

            let host: String
            
            if let h = parameter.testingHost, h != "localhost" {
                host = h
            } else {
                host = ProcessInfo.processInfo.environment["GITHUB_PG_TESTING_HOST"] ?? "localhost"
            }
            
            return .init(
                hostname: host,
                port: port,
                username: parameter.user,
                password: parameter.password,
                database: parameter.name,
                tls: .disable
            )
        }
        
        /// 永远不应直接调用
        public var config: SQLPostgresConfiguration {
            .init(
                hostname: "localhost",
                port: port,
                username: parameter.user,
                password: parameter.password,
                database: parameter.name,
                tls: .disable
            )
        }
        
        @inlinable
        public var json: [String: AnyCodable] {[
            "db_service_id": AnyCodable(dbServiceId.string),
            "db_fluent_id": AnyCodable(id.string),
            "port": AnyCodable(port),
            "parameter": AnyCodable(parameter.json)
        ]}
        
        @inlinable
        public var description: String {
            formatJson(json)
        }
    }
}

public extension Environment {
    protocol DriverKey: StorageKey, Sendable {
        static var label: String { get }
        static var isOptional: Bool { get }
        static var valueType: Environment.Types { get }
        static func apply(on storage: Storage, value: Any?) -> Storage
    }
}

extension Environment.DriverKey {
    @inlinable
    static var envName: String {
        (self.isOptional ? "#" : "") + self.label
    }
    
    @inlinable
    public static func apply(on storage: Storage, value: Any?) -> Storage {
        var new = storage
        guard let v = value as? Value else {
            fatalError("\(self.envName) 环境变量值解析失败")
        }
        new[self] = v
        return new
    }
}
