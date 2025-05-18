import Vapor
import WhooshingServer
import Cryptos

@main
enum Entrypoint {
    static func main() async throws {
        var e = try Environment.detect()
        try LoggingSystem.bootstrap(from: &e)
        
        let inline = try await InlineService.makeService()
        
        async let _ = try await ServiceBootstrap.run(woo: inline)
        async let _ = try await HttpsService.runService()
        async let _ = try await ApiService.runService(inline: inline)
    }
}
