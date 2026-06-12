import Foundation
import Vapor
import Collections
import OrderedCollections

/// API 模块初始化时将会从环境变量中读取认证模块的请求 URL
/// 因为它的加密机制依赖于该参数

extension Api {
    @usableFromInline
    struct ServicePara {
        @usableFromInline
        let authenticationURL: URL
    }
}

extension Api.ServicePara: Environment.Template {
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["authentication_url"] = .url
    }
    
    @inlinable
    init() {
        self.authenticationURL = URL(string: "https://example.com")!
    }
    
    @inlinable
    init(data: [String : Any], driverKeys: [any Environment.DriverKey.Type], extra: [String : Any]) {
        self.authenticationURL = data["authentication_url"] as! URL
    }
}
