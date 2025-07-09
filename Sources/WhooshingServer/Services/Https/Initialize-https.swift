import Vapor

/// 对于 HTTPS 模块无需进行其他配置，使用默认的 HTTPS 加密即可
/// 这需要外部设置证书和 Nginx 反向代理，但在这里无需多余配置

public enum Https: ServiceType {
    
    public static var envPrefix: String { "WHOOSHING_HTTPS_SERVICE" }
    
    @frozen
    public struct Debuging: DebugConfig, Sendable {
        public let config: Environment.Config
        
        @inlinable
        public init(config: Environment.Config = .init()) {
            self.config = config
        }
    }
    
    @usableFromInline
    internal static func config(_ woo: Whooshing<Https>) async throws(Failure) {
        woo.app.http.server.configuration.serviceName = "HTTPS"
    }
}
