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

public final class Whooshing<Service>: @unchecked Sendable where Service: ServiceType {
    public enum Env {
        case env(Environment)
        case debug(Service.Debuging)
    }
    
    public let app: Application
    public let config: Environment.Config
    public var logger: Logger { self.app.logger }
    
    internal let debugingData: Service.Debuging?
    
    public func execute() async throws { try await app.execute() }
    public func asyncShutdown() async throws { try await app.asyncShutdown() }
    public func executeWithAsyncShutdown() async throws {
        try await app.execute()
        try await app.asyncShutdown()
    }
    
    private init(app: Application, config: Environment.Config, debugingData: Service.Debuging?) {
        self.app = app
        self.config = config
        self.debugingData = debugingData
    }
    
    private static func makeService(environment: Env, config conf: (Self) async throws -> ()) async throws -> Self {
        let env: Environment
        let debuggingData: Service.Debuging?
        let config: Environment.Config
        
        switch environment {
        case .env(let e):
            env = e
            debuggingData = nil
            config = try Environment.get(with: Service.envPrefix)
        case .debug(let debugPara):
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

extension Whooshing where Service == Inline {
    public static func make(_ env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0)
        }
    }
}

extension Whooshing where Service == Https {
    public static func make(_ env: Env) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0)
        }
    }
}

extension Whooshing where Service == API {
    public static func make(_ env: Env, with inline: Whooshing<Inline>) async throws -> Self {
        try await makeService(environment: env) {
            try await Service.config($0, inlineClient: inline.inlineClient)
        }
    }
}
