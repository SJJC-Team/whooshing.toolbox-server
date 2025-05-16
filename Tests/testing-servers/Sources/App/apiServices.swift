import Vapor
import WhooshingServer
import Cryptos

struct ApiService {
    static func runService(inline: Whooshing<Inline>) async throws {
        let testPara = API.Debuging(config: .init(name: "Tesing-API-6502", port: 6502)) { authData in
            try API.Debuging.testingTokenAuth(with: Shared.apiClientTokenStr, encrypted: authData.tokenEncrypted)
        }
        try await ServiceBootstrap.runApiService(with: testPara, inline: inline, routes: routes)
    }
        
    static func routes(_ woo: Whooshing<WhooshingServer.API>, app: Application) throws {
        app.get("hello") { req in
            return "asfasdfafd"
        }
    }
}
