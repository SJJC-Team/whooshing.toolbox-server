import Vapor
import WhooshingClient
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging
import WhooshingWebSocket

public extension Whooshing where Service == Inline {
    var inlineClient: WhooshingClient { self.app.storage[InlineReqClient.self]! }
    var inlineWebSocket: any WhooshingWebSocket { self.app.storage[InlineWebSocket.self]! }
}

public enum Inline: ServiceType {
    
    public static var envPrefix: String { "WHOOSHING_INLINE_SERVICE" }
    
    public struct Debuging: DebugConfig {
        public let rootKey: Crypto.Symm.Key
        public let serviceId: UUID
        public let moduleDatas: [ModuleData]
        public let config: Environment.Config
        
        public init(
            rootKey: Crypto.Symm.Key,
            config: Environment.Config = .init(),
            serviceId: UUID = .init(),
            moduleDatas: [ModuleData] = []
        ) {
            self.rootKey = rootKey
            self.serviceId = serviceId
            self.moduleDatas = moduleDatas
            self.config = config
        }
    }
    
    public struct ModuleData: Content, Sendable, ThrowableDataConvertable {
        public let name: String
        public let serviceId: UUID
        public let connection: String?
        
        public init(name: String, serviceId: UUID, connection: String?) {
            self.name = name
            self.serviceId = serviceId
            self.connection = connection
        }
        
        public init(data: Data) throws {
            let paras = try [String: AnyThrowableDataConvertable](data: data)
            self.name = try paras["name"]!.cast(to: String.self)
            self.serviceId = try paras["serviceId"]!.cast(to: UUID.self)
            self.connection = try? paras["connection"]?.cast(to: String.self)
        }

        public func data() throws -> Data {
            let d: [String: (any ThrowableDataConvertable)?] = [
                "name": name,
                "serviceId": serviceId,
                "connection": connection
            ]
            return try d.filtered.anyValue.data()
        }
    }
    
    public enum ConfigErr: String, ErrList {
        public var domain: String { "woo.inline.sys.init.err" }
        case initializeFailed = "服务初始化失败"
    }
}

extension Inline {
    /// 配置 Inline 服务模块
    static func config(_ woo: Whooshing<Inline>) async throws {
        woo.app.http.server.configuration.serviceName = "INLINE"
        
        let serviceId: UUID
        if let debug = woo.debugingData {
            woo.app.logger.notice("获取模块 ID (Debuging, 不实际读取环境变量)")
            serviceId = debug.serviceId
        } else {
            woo.app.logger.debug("从环境变量中取得该服务模块的参数")
            serviceId = try ServicePara.parse(prefix: "WHOOSHING_INLINE_SERVICE_PRIVATE").serviceId
        }
        
        woo.app.logger.debug("注册 HTTP IO 加密模块")
        woo.app.use(httpIOHandler: HttpIOCrypto(app: woo))
        woo.app.logger.debug("注册服务来源验证中间件")
        woo.app.middleware.use(GuardMiddleware(serviceId: serviceId))
        woo.app.logger.debug("与模块管理器交互，取得可信服务列表并交换密钥")
        let rootKey = try await self.keyExchangeFromManager(woo)
        woo.app.logger.debug("创建 API Request Client")
        let client = InlineReqClient(eventLoop: woo.app.eventLoopGroup.next(), logger: woo.app.logger, byteBufferAllocator:.init() )
        let ioHandler = RequestIOCrypto(client: client, logger: woo.app.logger)
        client.ioHandler = ioHandler
        client.storage[Inline.RequestIOData.self] = .init(rootKey: rootKey, serviceID: serviceId)
        woo.app.storage[InlineReqClient.self] = client
        woo.app.logger.debug("创建 WebSocket Client")
        let wsClient = InlineWebSocket(client: client)
        woo.app.storage[InlineWebSocket.self] = wsClient
    }
    
    /// 与模块管理器交互，取得可信服务列表并交换密钥
    static func keyExchangeFromManager(_ woo: Whooshing<Inline>) async throws -> Crypto.Symm.Key {
        
        let rootKey: Crypto.Symm.Key
        
        if let debug = woo.debugingData {
            woo.app.logger.notice("获取服务根密钥以及服务模块参数列表 (Debuging, 不实际与模块管理器交互)")
            rootKey = debug.rootKey
            woo.app.storage[ServiceData.self] = ServiceData(
                rootKey: rootKey,
                moduleDatas: debug.moduleDatas
            )
        } else {
            woo.app.logger.trace("与模块管理器交互: 创建非对称公私钥")
            let keyPair = Crypto.Asym.makeCryptoKeyPair()
            woo.app.logger.trace("与模块管理器交互: 向模块管理器请求取得服务模块信息，首先将自己的公钥发出")
            let res = try await woo.app.client.post(woo.config.managerUrl.toUri(with: "/params/init").uri) { postRequest in
                try postRequest.content.encode(keyPair.public, as: .json)
            }
            guard res.status == .ok else { throw ConfigErr.initializeFailed.d("请求模块管理器的结果为: \(res.status)", 10010) }
            woo.app.logger.trace("与模块管理器交互: 解包服务器回复")
            let paras = try res.content.decode(InitParaRes.self)
            woo.app.logger.trace("与模块管理器交互: 生成共享密钥")
            let sharedKey = try Crypto.Asym.keyEncapsulate(key: keyPair.private, partyPublic: paras.pub, salt: Crypto.hash("manager.shared.key"), info: "")
            woo.app.logger.trace("与模块管理器交互: 解密得到服务根密钥")
            rootKey = try Crypto.Symm.decrypt(paras.root, key: sharedKey)
            woo.app.logger.trace("与模块管理器交互: 保存到上下文")
            woo.app.storage[ServiceData.self] = try ServiceData(
                rootKey: rootKey,
                moduleDatas: paras.modules.map { try Crypto.Symm.decrypt($0, key: sharedKey) }
            )
        }
        
        return rootKey
        
        struct InitParaRes: Content {
            let pub: Crypto.Asym.CPublicKey
            let root: Data
            let modules: [Data]
        }
    }
}
