import Cryptos
import Foundation
import NIO
import Logging
import WhooshingClient
import WhooshingWebSocket
@testable import WhooshingServer

struct TestingShared {
    static let rootKey = Crypto.Symm.Key(data: Data(base64Encoded: rootKeyStr)!)
    static let rootKeyStr = "0apYyvRtLuo7l07zuqbEjFIxDFZ1sIWabKM9mMOOIzQ="
    
    static let wrongRootKey = Crypto.Symm.Key(data: Data(base64Encoded: wrongRootKeyStr)!)
    static let wrongRootKeyStr = "Mzn/h5zDnIdi4C3yHaRMG62DhC9qYt8q4SfOCV338hY="
    
    static let apiClientCredential = "bRRPIiYbt0t4RzfqeeHSkg=="
    
    static let wrongApiClientCredential = "PXt3S3oMWfHIE7wb1S1nMg=="
    
    static let apiClientToken = Crypto.Symm.Key(data: Data(base64Encoded: apiClientTokenStr)!)
    static let apiClientTokenStr = "jXTz4vTQk0O/XFIjWQIHLC7z9/E0/4VtEb+LkF8IcA4="
    
    static let wrongApiClientToken = Crypto.Symm.Key(data: Data(base64Encoded: wrongApiClientTokenStr)!)
    static let wrongApiClientTokenStr = "9cCat+omad2WPRetG0VdqSdVhBPVz5kXJ2DssJtQshI="
    
    static let serviceIds = [
        UUID(uuidString: "F1ECC1D7-6E19-4F50-9B89-68FAA332B415")!,
        UUID(uuidString: "2AC424F7-F26A-4EA4-BE44-202ABC7CC514")!,
        UUID(uuidString: "74854475-1C1A-48E2-BAC9-E9C752942F88")!,
    ]
}

func makeInlineClient(rootKey: Crypto.Symm.Key, serviceId: UUID) -> InlineReqClient {
    let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    var logger = Logger(label: "Testing-Inline")
//    logger.logLevel = .trace
    let client = InlineReqClient(eventLoop: eventLoop.next(), logger: logger, byteBufferAllocator: .init())
    let ioHandler = Inline.RequestIOCrypto(client: client, logger: logger)
    client.ioHandler = ioHandler
    client.storage[Inline.RequestIOData.self] = .init(rootKey: rootKey, serviceID: serviceId)
    return client
}

func makeInlineWebSocket(rootKey: Crypto.Symm.Key, serviceId: UUID) -> InlineWebSocket {
    let client = makeInlineClient(rootKey: rootKey, serviceId: serviceId)
    return .init(client: client)
}

func makeApiClient(credential: String, token: String) -> ApiClient {
    let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    var logger = Logger(label: "Testing-Api")
//    logger.logLevel = .trace
    return ApiClient(credential: credential, token: token, eventLoop: eventLoop.next(), logger: logger)
}

func makeApiWebSocket(credential: String, token: String) -> ApiWebSocket {
    let client = makeApiClient(credential: credential, token: token)
    return .init(client: client)
}


actor OrderedIndexTracker {
    private var received = Set<Int>()
    private let maxIndex: Int
    init(maxIndex: Int) { self.maxIndex = maxIndex }
    func insert(_ index: Int) { received.insert(index) }
    func isReady() -> Bool { received.count == (maxIndex + 1) }
}

actor Counter {
    private var max: Int
    var value = 0
    
    init(max: Int, value: Int = 0) {
        self.max = max
        self.value = value
    }
    
    func next() -> Int {
        let current = value
        value += 1
        return current
    }
    
    var isLast: Bool { value == max }
}
