import FluentPostgresDriver
import Vapor

public extension Environment {
    struct Config: Sendable {
        public let name: String
        public let port: Int
        public let databases: [DB]
        public let managerUrl: URL
        public let domain: String?
        
        public init() { self = Self(name: "Testing") }
        
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
    
    struct DB: Sendable {
        public let name: String
        public let port: Int
        public let user: String
        internal let password: String
        
        public let maxConnectionsPerEventLoop: Int
        public let connectionPoolTimeout: TimeAmount
        public let sqlLogLevel: Logger.Level
        
        public init() { self = Self(name: "postgres") }
        
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
        
        public var id: DatabaseID { .init(string: name) }
        
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
