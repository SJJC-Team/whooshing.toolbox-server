import ErrorHandle

public extension Whooshing {
    @frozen
    enum Errcase: String, ErrList, Sendable {
        case environmentFailed = "环境变量配置失败"
        case vaporAppCreateFailed = "Vapor App 创建失败"
        case serviceInitFailed = "服务初始化配置失败"
        case executionFailed = "运行时出错，错误未被处理"
        case shutdownFailed = "关闭服务时出错"
    }
}

public extension Inline {
    @frozen
    enum Errcase: String, ErrList, Sendable {
        case initFailed = "服务初始化失败"
        case jsonDecodeFailed = "交接协议信息 json 解码失败"
        case keyDecodeFailed = "密钥信息解码失败"
        case keyEncapsulateFailed = "密钥交换失败"
        case serviceAuthFailed = "服务模块 ID 验证失败"
        case internalFailure = "内部错误"
    }
}

public extension Api {
    @frozen
    enum Errcase: String, ErrList, Sendable {
        case initFailed = "服务初始化失败"
        case requestFailed = "向认证模块请求失败"
        case badRequest = "无效的请求"
        case jsonEncodeFailed = "交接协议信息 json 编码失败"
        case jsonDecodeFailed = "交接协议信息 json 解码失败"
        case authDataDecodeFailed = "用户认证数据解码失败"
        case authFailed = "用户认证被拒"
        case internalFailure = "内部错误"
    }
}

public extension Https {
    @frozen
    enum Errcase: String, ErrList, Sendable {
        case internalFailure = "内部错误"
    }
}
