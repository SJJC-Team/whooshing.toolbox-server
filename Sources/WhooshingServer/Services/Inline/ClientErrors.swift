import ErrorHandle
import WhooshingClient

@frozen
public enum InlineClientErrcase: String, ErrList, Sendable {
    case badRequest = "无效的请求"
    case badResponse = "无效的响应"
    case decryptFailed = "交接协议信息解密失败"
    case keyEncapsulateFailed = "密钥交换失败"
    case jsonEncodeFailed = "交接协议信息 json 编码失败"
    case dataDecodeFailed = "交接协议信息 data 解码失败"
    case tcpChannelAssignFailed = "TCP 通道分配失败"
    case tcpSendFailed = "TCP 通道数据发送失败"
    case tcpHandleRemoveFailed = "TCP 处理器移除失败"
    case internalFailure = "内部错误"
}
