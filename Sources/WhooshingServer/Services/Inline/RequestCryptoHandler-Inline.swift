import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import NIOAdvanced
import Logging
import WhooshingClient

/// 该文件从 HTTP 基层 TCP 实现了请求加密的加解密算法。保证整个请求报文都是被加密或被解密的(解密或加密取决于是入站请求还是出站响应)
/// 是与 ReqClient 配套实现请求加密逻辑的

extension InlineClient {
    var requestIoData: Inline.RequestIOData! { self.storage[Inline.RequestIOData.self] }
}

extension Inline {
    @frozen
    public enum RequestCryptoErrcase: String, ErrList {
        case requestEncryptFailed = "请求数据加密时失败"
        case responseDecryptFailed = "响应数据解密时失败"
        
        case internalFailure = "内部错误"
    }
    
    final class RequestIOData: SendableStorage.Key, Sendable {
        typealias Value = RequestIOData
        let rootKey: Crypto.Symm.Key
        let serviceID: UUID
        let connectionValidate: SendableDictionary<ObjectIdentifier, Bool> = .init()
        let connectionKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        let readingBufferDatas: SendableDictionary<ObjectIdentifier, ByteBuffer> = .init()
        
        init(rootKey: Crypto.Symm.Key, serviceID: UUID) {
            self.rootKey = rootKey
            self.serviceID = serviceID
        }
    }
    
    /// 实现 HTTP Request 的加解密
    struct RequestIOCrypto: RequestCryptoIOHandler, Sendable {
        weak var client: InlineClient!
        let logger: Logger
        
        var isAvaliable: Bool { client != nil }
        
        /// 发送请求时，进行编码并加密
        func send(data: NIOCore.ByteBuffer, context: NIOCore.ChannelHandlerContext) -> EventLoopRes<ByteBuffer, RequestCryptoErrcase> {
            context.eventLoop.makeResultWithTask { () throws(RequestCryptoErrcase.ErrType) in
                guard data.readableBytes > 0 else { return data }
                let cipher: Data
                let id = ObjectIdentifier(context.channel)
                logger.trace("Inline.Client.HTTP-发送请求，进行加密(key: \(client.requestIoData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                if let key = client.requestIoData.connectionKeys[id] {
                    cipher = try required(throws: RequestCryptoErrcase.requestEncryptFailed) {
                        try Crypto.Symm.encrypt(data, key: key).get()
                    }
                } else {
                    cipher = try required(throws: RequestCryptoErrcase.requestEncryptFailed) {
                        try Crypto.Symm.encrypt(data, key: client.requestIoData.rootKey).get()
                    }
                }
                let buffer = ByteBuffer(data: cipher)
                return buffer
            }
        }
        
        /// 收到响应时，进行解密并解码
        func get(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopRes<ByteBuffer, RequestCryptoErrcase> {
            context.eventLoop.makeResultWithTask { () throws(RequestCryptoErrcase.ErrType) in
                guard data.readableBytes > 0 else { return data }
                let id = ObjectIdentifier(context.channel)
                var plain: ByteBuffer
                logger.trace("Inline.Client.HTTP-收到响应，进行解密(key: \(client.requestIoData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                if let key = client.requestIoData.connectionKeys[id] {
                    plain = try required(throws: RequestCryptoErrcase.responseDecryptFailed) {
                        try Crypto.Symm.decrypt(.init(buffer: data), key: key).get()
                    }
                } else {
                    plain = try required(throws: RequestCryptoErrcase.responseDecryptFailed) {
                        try Crypto.Symm.decrypt(.init(buffer: data), key: client.requestIoData.rootKey).get()
                    }
                }
                return plain
            }
        }

        // 连线建立
        func connectionStart(context: ChannelHandlerContext) -> EventLoopRes<Void, RequestCryptoErrcase> {
            logger.debug("Inline.Client-连线建立: \(context.channel.clientAddrInfo)")
            return context.eventLoop.makeSucceededVoidResult()
        }
        
        // 连线结束，进行清理
        func connectionEnd(context: ChannelHandlerContext) -> EventLoopRes<Void, RequestCryptoErrcase> {
            logger.debug("Inline.Client-连线结束: \(context.channel.clientAddrInfo)")
            let id = ObjectIdentifier(context.channel)
            if let client = self.client {
                client.requestIoData.connectionKeys[id] = nil
                client.requestIoData.connectionValidate[id] = nil
                client.requestIoData.readingBufferDatas[id] = nil
            }
            return context.eventLoop.makeSucceededVoidResult()
        }
    }
}
