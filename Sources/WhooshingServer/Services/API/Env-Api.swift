import Foundation
import Vapor
import OrderedCollections

/// API 模块初始化时将会从环境变量中读取认证模块的请求 URL
/// 因为它的加密机制依赖于该参数

extension Api {
    public enum AuthenticationTarget: Sendable {
        case itself
        case url(URL)
        
        static let selfURL: URI = "/account/authenticate" // 如果身份验证目标为自己，则需要提供该 URL
    }
    
    @usableFromInline
    struct ServicePara {
        @usableFromInline
        let authenticationTarget: AuthenticationTarget
    }
}

extension Api.ServicePara: Environment.Template {
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["authentication_target_type"] = .string()
        origin["authentication_target_value"] = .string(optional: true)
    }
    
    @inlinable
    init() {
        self.authenticationTarget = .itself
    }
    
    @inlinable
    init(data: [String : Any], driverKeys: [any Environment.DriverKey.Type], extra: [String : Any]) {
        let type = data["authentication_target_type"] as! String
        if type == "SELF" {
            self.authenticationTarget = .itself
        } else if type == "URL" {
            let value = data["authentication_target_value"] as! URL
            self.authenticationTarget = .url(value)
        }
        fatalError("环境变量所读取的 AUTHENTICATION_TARGET_TYPE 有误")
    }
}
