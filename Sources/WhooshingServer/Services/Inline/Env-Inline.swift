import Foundation
import Vapor
import OrderedCollections

/// INLINE 模块初始化时将会从环境变量中读取为自己分配的服务 ID
/// 因为它的加密机制依赖于该参数

extension Inline {
    @usableFromInline
    struct ServicePara {
        /// 服务 ID，用于 Inline 连接的合法性验证，被 internal 保护，不应被外界读取
        /// 与 Environment.Config 的 moduleId 不同，切勿混用
        @usableFromInline
        let serviceId: UUID
    }
}

extension Inline.ServicePara: Environment.Template {
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["service_id"] = .uuid()
    }
    
    @inlinable
    init() {
        self.serviceId = .init()
    }
    
    @inlinable
    init(data: [String : Any], driverKeys: [any Environment.DriverKey.Type], extra: [String: Any]) {
        self.serviceId = data["service_id"] as! UUID
    }
}
