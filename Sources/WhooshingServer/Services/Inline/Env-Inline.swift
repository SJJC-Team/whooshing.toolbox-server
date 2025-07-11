import Foundation
import Vapor
import Collections

/// INLINE 模块初始化时将会从环境变量中读取为自己分配的服务 ID
/// 因为它的加密机制依赖于该参数

extension Inline {
    @usableFromInline
    struct ServicePara {
        @usableFromInline
        let serviceId: UUID
    }
}

extension Inline.ServicePara: Environment.Template {
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["service_id"] = .uuid
    }
    
    @inlinable
    init() {
        self.serviceId = .init()
    }
    
    @inlinable
    init(data: [String : Any], extra: [String: Any]) {
        self.serviceId = data["service_id"] as! UUID
    }
}
