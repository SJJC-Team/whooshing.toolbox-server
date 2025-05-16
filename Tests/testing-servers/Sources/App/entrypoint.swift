import Vapor
import WhooshingServer
import Cryptos

@main
enum Entrypoint {
    static func main() async throws {
        var e = try Environment.detect()
        try LoggingSystem.bootstrap(from: &e)
        
        let inline1 = try await InlineService1.makeService()
        
        async let _ = try await ServiceBootstrap.run(woo: inline1)
        async let _ = try await InlineService2.runService()
        async let _ = try await ApiService.runService(inline: inline1)
    }
}
