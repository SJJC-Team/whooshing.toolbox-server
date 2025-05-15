import Vapor

/// 对于 HTTPS 模块无需进行其他配置，使用默认的 HTTPS 加密即可
/// 这需要外部设置证书和 Nginx 反向代理，但在这里无需多余配置

public enum Https: ServiceType {
    
    public static var envPrefix: String { "WHOOSHING_HTTPS_SERVICE" }
    
    public struct Testing: TestConfig {
        public let config: Environment.Config
        
        public init(config: Environment.Config = .init()) {
            self.config = config
        }
    }
    
    internal static func config(_ woo: Whooshing<Https>) async throws {
        woo.app.http.server.configuration.serviceName = "HTTPS"
    }
}
