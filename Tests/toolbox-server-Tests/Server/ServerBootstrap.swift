import Cryptos
import Foundation
import WhooshingServer
import Vapor
import Logging
import LoggingAdvanced

struct ServiceBootstrap {
    
    static func run<T>(woo: Whooshing<T>) async throws {
        do {
            try await woo.execute().get()
        } catch {
            try await woo.asyncShutdown().get()
            throw error
        }
    }
    
    static func runHttpsService(with testPara: Https.Debuging, routes: (Whooshing<Https>, Application) throws -> ()) async throws {
        var logger = Logger(label: "client.https")
        logger.logLevel = TestingShared.logLevel
        let woo = try await Whooshing<Https>.make(.detect(testPara), logger: logger).get()
        try routes(woo, woo.app)
        Entrypoint.httpsApp = woo
        try await run(woo: woo)
    }

    static func runInlineService(with testPara: Inline.Debuging, routes: (Whooshing<Inline>, Application) throws -> ()) async throws {
        var logger = Logger(label: "client.inline")
        logger.logLevel = TestingShared.logLevel
        let woo = try await Whooshing<Inline>.make(.detect(testPara), logger: logger).get()
        try routes(woo, woo.app)
        try await run(woo: woo)
    }
    
    static func runApiService(with testPara: Api.Debuging, inline: Whooshing<Inline>, routes: (Whooshing<Api>, Application) throws -> ()) async throws {
        var logger = Logger(label: "client.api")
        logger.logLevel = TestingShared.logLevel
        let woo = try await Whooshing<Api>.make(.detect(testPara), with: inline, logger: logger).get()
        try routes(woo, woo.app)
        Entrypoint.apiApp = woo
        try await run(woo: woo)
    }
}
