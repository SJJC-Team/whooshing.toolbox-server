import Foundation
import Vapor

/// INLINE 模块初始化时将会从环境变量中读取为自己分配的服务 ID
/// 因为它的加密机制依赖于该参数

extension Inline {
    struct ServicePara {
        let serviceId: UUID
    }
}

extension Inline.ServicePara: Environment.Template {
    static var envs: [String : Environment.Types] { ["service_id": .uuid] }
    init() { self.serviceId = .init() }
    init(data: [String : Any]) {
        self.serviceId = data["service_id"] as! UUID
    }
}
