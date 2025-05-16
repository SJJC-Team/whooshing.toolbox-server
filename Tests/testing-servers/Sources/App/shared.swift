import Cryptos
import Foundation
import WhooshingServer
import Vapor

struct Shared {
    static let rootKey = Crypto.Symm.Key(data: Data(base64Encoded: rootKeyStr)!)
    static let rootKeyStr = "0apYyvRtLuo7l07zuqbEjFIxDFZ1sIWabKM9mMOOIzQ="
    
    static let apiClientCredential = "bRRPIiYbt0t4RzfqeeHSkg=="

    static let apiClientToken = Crypto.Symm.Key(data: Data(base64Encoded: apiClientTokenStr)!)
    static let apiClientTokenStr = "jXTz4vTQk0O/XFIjWQIHLC7z9/E0/4VtEb+LkF8IcA4="

    static let serviceIds = [
        UUID(uuidString: "F1ECC1D7-6E19-4F50-9B89-68FAA332B415")!,
        UUID(uuidString: "2AC424F7-F26A-4EA4-BE44-202ABC7CC514")!,
        UUID(uuidString: "74854475-1C1A-48E2-BAC9-E9C752942F88")!,
    ]
}


struct ServiceBootstrap {
    
    static func run<T>(woo: Whooshing<T>) async throws {
        do {
            try await woo.executeWithAsyncShutdown()
        } catch {
            try await woo.asyncShutdown()
            throw error
        }
    }
    
    static func runInlineService(with testPara: Inline.Debuging, routes: (Whooshing<Inline>, Application) throws -> ()) async throws {
        let woo = try await Whooshing<Inline>.make(.independentDebug(testPara))
        try routes(woo, woo.app)
        try await run(woo: woo)
    }
    
    static func runApiService(with testPara: API.Debuging, inline: Whooshing<Inline>, routes: (Whooshing<API>, Application) throws -> ()) async throws {
        let woo = try await Whooshing<API>.make(.independentDebug(testPara), with: inline)
        try routes(woo, woo.app)
        try await run(woo: woo)
    }
}
