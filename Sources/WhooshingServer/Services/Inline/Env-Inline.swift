import Foundation
import Vapor

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
    @inlinable static var envs: [String : Environment.Types] { ["service_id": .uuid] }
    @inlinable init() { self.serviceId = .init() }
    @inlinable init(data: [String : Any]) {
        self.serviceId = data["service_id"] as! UUID
    }
}
