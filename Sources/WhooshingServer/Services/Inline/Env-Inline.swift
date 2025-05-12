import Foundation

/// INLINE 模块初始化时将会从环境变量中读取为自己分配的服务 ID
/// 因为它的加密机制依赖于该参数

extension Inline {
    struct ServicePara {
        let serviceID: UUID
    }
}

extension Inline.ServicePara: Env.Template {
    static var envs: [String : Env.Types] { ["service_id": .uuid] }
    init() { self.serviceID = .init() }
    init(data: [String : Any]) {
        self.serviceID = data["service_id"] as! UUID
    }
}
