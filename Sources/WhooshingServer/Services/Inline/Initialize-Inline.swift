import Vapor
import WhooshingClient
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging
import WhooshingWebSocket

public extension Whooshing where Service == Inline {
    var inlineClient: AnyWhooshingClient<InlineClientErrcase> { self.app.storage[AnyWhooshingClient<InlineClientErrcase>.self]! }
    var inlineWebSocket: any WhooshingWebSocket { self.app.storage[InlineWebSocket.self]! }
}

@frozen
public enum Inline: ServiceType {
    
    @inlinable
    public static var envPrefix: String { "WHOOSHING_INLINE_SERVICE" }
    
    /// 用于在无依赖 debug (Whooshing.Env.independentDebug) 模式下运行的依赖参数
    ///
    /// 伪造该模块所必须的服务根密钥，服务 Id，以及所有模块的服务 ID 以无依赖运行
    ///
    /// > 在一般的 .production 或 .debug 模式下，
    /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
    /// 而在独立无依赖运行模式下，需要手动提供
    @frozen
    public struct Debuging: DebugConfig, Sendable {
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
        @inlinable
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
    
    @frozen
    public struct ModuleData: Content, Sendable, ThrowableDataConvertable {
        
        @frozen
        public enum Errcase: String, ErrList {
            case decodeFailed = "解码失败"
            case encodeFailed = "编码失败"
        }
        
        public let name: String
        public let serviceId: UUID
        public let connection: String?
        
        @inlinable
        public init(name: String, serviceId: UUID, connection: String?) {
            self.name = name
            self.serviceId = serviceId
            self.connection = connection
        }
        
        @inlinable
        public var dataRes: Res<Data, Errcase> {
            let d: [String: (any ThrowableDataConvertable)?] = [
                "name": name,
                "serviceId": serviceId,
                "connection": connection
            ]
            return .init(throws: Errcase.decodeFailed) {
                try d.filtered.anyValue.dataRes.get()
            }
        }
        
        @inlinable
        public static func make(data: Data) -> Res<Self, Errcase> {
            .init { () throws(Errcase.ErrType) in
                let paras = try required(throws: Errcase.encodeFailed, "类型擦除转换数据失败") {
                    try [String: AnyThrowableDataConvertable].make(data: data).get()
                }
                
                return Self.init(
                    name: try requireData(from: paras, for: "name"),
                    serviceId: try requireData(from: paras, for: "serviceId"),
                    connection: try requireData(from: paras, for: "connection")
                )
            }
        }
        
        @usableFromInline
        static func requireData<T>(
            from paras: [String: AnyThrowableDataConvertable],
            for field: String
        ) throws(Errcase.ErrType) -> T where T: EncodingThrowableDataConvertable {
            guard let data = paras[field] else {
                throw Errcase.encodeFailed.d("\(field) 数据缺失")
            }
            
            let res = try required(throws: Errcase.encodeFailed) {
                try data.cast(to: T.self).get()
            }
            
            return res
        }
    }
}

extension Inline {
    /// 配置 Inline 服务模块
    @usableFromInline
    static func config(_ woo: Whooshing<Inline>) async throws(Failure) {
        woo.app.http.server.configuration.serviceName = "INLINE"
        
        let serviceId: UUID
        if let debug = woo.debugingData {
            woo.app.logger.notice("获取模块 ID (Debuging, 不实际读取环境变量)")
            serviceId = debug.serviceId
        } else {
            woo.app.logger.debug("从环境变量中取得该服务模块的参数")
            serviceId = try required(throws: Errcase.initFailed, "环境变量解析失败") {
                try ServicePara.parse(prefix: "WHOOSHING_INLINE_SERVICE_PRIVATE").serviceId
            }
        }
        
        woo.app.logger.debug("注册 HTTP IO 加密模块")
        woo.app.use(httpIOHandler: .init(HttpIOCrypto(app: woo)))
        woo.app.logger.debug("注册服务来源验证中间件")
        woo.app.middleware.use(GuardMiddleware(serviceId: serviceId))
        woo.app.logger.debug("与模块管理器交互，取得可信服务列表并交换密钥")
        let rootKey = try await self.keyExchangeFromManager(woo)
        woo.app.logger.debug("创建 API Request Client")
        let client = InlineClient(eventLoop: woo.app.eventLoopGroup.next(), logger: woo.app.logger, byteBufferAllocator:.init() )
        let ioHandler = RequestIOCrypto(client: client, logger: woo.app.logger)
        client.ioHandler = ioHandler
        client.storage[Inline.RequestIOData.self] = .init(rootKey: rootKey, serviceID: serviceId)
        woo.app.storage[AnyWhooshingClient<InlineClientErrcase>.self] = .init(client)
        woo.app.logger.debug("创建 WebSocket Client")
        let wsClient = InlineWebSocket(client: client)
        woo.app.storage[InlineWebSocket.self] = wsClient
    }
    
    struct InitParaRes: Content {
        let pub: Crypto.Asym.CPublicKey
        let root: Data
        let modules: [Data]
    }
    
    /// 与模块管理器交互，取得可信服务列表并交换密钥
    static func keyExchangeFromManager(_ woo: Whooshing<Inline>) async throws(Failure) -> Crypto.Symm.Key {
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
            let res = try await required(throws: Errcase.initFailed, "向模块管理器请求失败") {
                try await woo.app.client.post(woo.config.managerUrl.toUri(with: "/params/init").uri) { postRequest in
                    try postRequest.content.encode(keyPair.public, as: .json)
                }
            }
            guard res.status == .ok else {
                throw Errcase.initFailed.d("请求模块管理器的结果为: \(res.status)")
            }
            
            woo.app.logger.trace("与模块管理器交互: 解包服务器回复")
            let paras = try required(throws: Errcase.initFailed, "从模块管理器解包服务参数失败") {
                try res.content.decode(InitParaRes.self)
            }
            
            woo.app.logger.trace("与模块管理器交互: 生成共享密钥")
            let sharedKey = try required(throws: Errcase.initFailed, "密钥交换失败") {
                try Crypto.Asym.keyEncapsulate(
                    key: keyPair.private,
                    partyPublic: paras.pub,
                    salt: Crypto.hash("manager.shared.key").get(),
                    info: ""
                ).get()
            }
            
            woo.app.logger.trace("与模块管理器交互: 解密得到服务根密钥")
            rootKey = try required(throws: Errcase.initFailed, "根密钥数据解密失败") {
                try Crypto.Symm.decrypt(paras.root, key: sharedKey).get()
            }
            
            woo.app.logger.trace("与模块管理器交互: 保存到上下文")
            let moduleDatas: [ModuleData] = try required(throws: Errcase.initFailed, "解码模块数据失败") {
                try paras.modules.map { try Crypto.Symm.decrypt($0, key: sharedKey).get() }
            }
            
            woo.app.storage[ServiceData.self] = ServiceData(
                rootKey: rootKey,
                moduleDatas: moduleDatas
            )
        }
        
        return rootKey
    }
}

extension AnyWhooshingClient: @retroactive StorageKey {
    public typealias Value = AnyWhooshingClient<Errcase>
}
