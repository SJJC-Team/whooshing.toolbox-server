import Vapor

/// 对于 HTTPS 模块无需进行其他配置，使用默认的 HTTPS 加密即可
/// 这需要外部设置证书和 Nginx 反向代理，但在这里无需多余配置

public enum Https: ServiceType {
    
    public static var name: String { "https" }
    
    @frozen
    public struct Debuging: DebugConfig, Sendable {
        /// 服务配置，原来通过 Whooshing 系统环境变量自动获取
        ///
        /// 指定诸如监听地址，PostgreSQL 数据库的连线参数，等等
        /// 见 ``Environment.Config``
        public let config: Environment.Config
        
        /// 控制台日志等级，该等级为策略层等级(目标侧闸门)
        /// 具体被打印的日志等级仍然取决于 logger 本身的应用层闸门等级
        public let consoleLogLevel: Logger.Level
        
        /// 提供参数初始化 Https 依赖参数
        ///
        /// - Parameters:
        ///   - config: 服务配置
        ///   - consoleLogLevel: 控制台日志等级，默认为 trace, 该等级为策略层等级(目标侧闸门), 具体被打印的日志等级仍然取决于 logger 本身的应用层闸门等级
        /// - Returns:
        ///   初始化的 Https 依赖参数
        @inlinable
        public init(
            config: Environment.Config,
            consoleLogLevel: Logger.Level = .trace
        ) {
            self.config = config
            self.consoleLogLevel = consoleLogLevel
        }
    }
    
    @usableFromInline
    internal static func config(_ woo: Whooshing<Https>) async throws(Failure) {
        woo.app.http.server.configuration.serviceName = "HTTPS"
    }
}
