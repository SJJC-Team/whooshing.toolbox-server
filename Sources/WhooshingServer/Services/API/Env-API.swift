import Foundation

/// API 模块初始化时将会从环境变量中读取认证模块的请求 URL
/// 因为它的加密机制依赖于该参数

extension API {
    struct ServicePara {
        let authenticationURL: URL
    }
}

extension API.ServicePara: Env.Template {
    static var envs: [String : Env.Types] { ["authentication_url": .url] }
    init() { self.authenticationURL = URL(string: "https://example.com")! }
    init(data: [String : Any]) {
        self.authenticationURL = data["authentication_url"] as! URL
    }
}
