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
    
    /// 用于在无依赖 debug (Whooshing.Env.independentDebug) 模式下运行的依赖参数
    ///
    /// 伪造该模块所必须的服务根密钥，服务 Id，以及所有模块的服务 ID 以无依赖运行
    ///
    /// > 在一般的 .production 或 .debug 模式下，
    /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
    /// 而在独立无依赖运行模式下，需要手动提供
    public struct Debuging: DebugConfig {
        /// 服务根密钥，用于初始化 Inline 服务
        public let rootKey: Crypto.Symm.Key
        /// 该服务模块的服务 ID，用于初始化 Inline 服务，并作为与客户端通讯的首次加密密钥
        public let serviceId: UUID
        /// 其他服务模块的信息，用于验证服务来源是否可信，
        /// 若有服务模块的服务 ID 不在此列，该服务模块将拒绝此连线
        public let moduleDatas: [ModuleData]
        /// 服务配置，原来通过 Whooshing 系统环境变量自动获取
        ///
        /// 指定诸如监听地址，PostgreSQL 数据库的连线参数，等等
        /// 见 ``Environment.Config``
        public let config: Environment.Config
        
        /// 提供参数初始化 Inline 依赖参数
        ///
        /// - Parameters:
        ///   - rootKey: 服务根密钥，用于初始化 Inline 服务
        ///   - config: 服务配置
        ///   - serviceId: 该服务模块的服务 ID
        ///   - moduleDatas: 其他服务模块的信息，用于验证服务来源是否可信
        /// - Returns:
        ///   初始化的 Inline 依赖参数
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
