import Vapor

/// 对于 HTTPS 模块无需进行其他配置，使用默认的 HTTPS 加密即可
/// 这需要外部设置证书和 Nginx 反向代理，但在这里无需多余配置

enum Https {
    static func config(_ app: Application) async throws {
        app.http.server.configuration.serviceName = "HTTPS"
    }
}
