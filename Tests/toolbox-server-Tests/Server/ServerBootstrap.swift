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
}
