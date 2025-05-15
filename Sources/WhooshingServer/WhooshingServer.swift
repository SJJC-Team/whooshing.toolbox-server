import Vapor
import Fluent
import FluentPostgresDriver
import ErrorHandle
import WhooshingClient
import Cryptos

public protocol ServiceType {
    associatedtype Testing: TestConfig
    static var envPrefix: String { get }
}

public protocol TestConfig {
    var config: Environment.Config { get }
}

public final class Whooshing<Service>: @unchecked Sendable where Service: ServiceType {
    public enum Env {
        case env(Environment)
        case testing(Service.Testing)
    }
    
    public let app: Application
    public let config: Environment.Config
    public var logger: Logger { self.app.logger }
    
    internal let testingData: Service.Testing?
    
    public func run() async throws {
        try await app.execute()
        try await app.asyncShutdown()
    }
    
    private init(app: Application, config: Environment.Config, testingData: Service.Testing?) {
        self.app = app
        self.config = config
        self.testingData = testingData
    }
    
    private static func makeService(environment: Env, config conf: (Self) async throws -> ()) async throws -> Self {
        let env: Environment
        let testingData: Service.Testing?
        let config: Environment.Config
        
        switch environment {
        case .env(let e):
            env = e
            testingData = nil
            config = try Environment.get(with: Service.envPrefix)
        case .testing(let testPara):
            env = .testing
            testingData = testPara
            config = testPara.config
        }
        
        let app = try await Application.make(env)
        app.http.server.configuration.port = config.port
        for db in config.databases { app.databases.use(db.config, as: db.id) }
        let service = Self(app: app, config: config, testingData: testingData)
        try await conf(service)
        return service
    }
}

extension Whooshing where Service == Inline {
    public static func make(env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0)
        }
    }
}

extension Whooshing where Service == Https {
    public static func make(env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0)
        }
    }
}

extension Whooshing where Service == API {
    public static func make(with inline: Whooshing<Inline>, env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0, inlineClient: inline.inlineClient)
        }
    }
}
