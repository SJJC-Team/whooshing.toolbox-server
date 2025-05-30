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
    
    static let inlineListenPort = 6500
    static let httpsListenPort = 6501
    static let apiListenPort = 6502
    
    static let inlineServiceListening = isTCPPortOpen(inlineListenPort)
    static let httpsServiceListening = isTCPPortOpen(httpsListenPort)
    static let apiServiceListening = isTCPPortOpen(apiListenPort)
    
    static let normalFilePath = "/Users/clwang/Downloads/test.png"
    static let normalFileName = "test.png"
    static let largeFilePath = "/Users/clwang/Downloads/large.zip"
    static let largeFileName = "large.zip"
    
    static let serviceIds = [
        UUID(uuidString: "F1ECC1D7-6E19-4F50-9B89-68FAA332B415")!,
        UUID(uuidString: "2AC424F7-F26A-4EA4-BE44-202ABC7CC514")!,
        UUID(uuidString: "74854475-1C1A-48E2-BAC9-E9C752942F88")!,
    ]
}

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

func makeHttpsClient() -> HttpsClient {
    let logger = Logger(label: "Testing-Https")
//    logger.logLevel = .trace
    return HttpsClient(in: eventLoopGroup.next(), logger: logger)
}

func makeInlineClient(rootKey: Crypto.Symm.Key, serviceId: UUID) -> InlineClient {
    let logger = Logger(label: "Testing-Inline")
//    logger.logLevel = .trace
    let client = InlineClient(eventLoop: eventLoopGroup.next(), logger: logger, byteBufferAllocator: .init())
    let ioHandler = Inline.RequestIOCrypto(client: client, logger: logger)
    client.ioHandler = ioHandler
    client.storage[Inline.RequestIOData.self] = .init(rootKey: rootKey, serviceID: serviceId)
    return client
}

func makeApiClient(credential: String, token: String) -> ApiClient {
    let logger = Logger(label: "Testing-Api")
//    logger.logLevel = .trace
    return ApiClient(credential: credential, token: token, eventLoop: eventLoopGroup.next(), logger: logger)
}

func makeHttpsWebSocket() -> HttpsWebSocket {
    let logger = Logger(label: "Testing-HTTPS")
    return HttpsWebSocket(in: eventLoopGroup.next(), logger: logger)
}

func makeInlineWebSocket(rootKey: Crypto.Symm.Key, serviceId: UUID) -> InlineWebSocket {
    let client = makeInlineClient(rootKey: rootKey, serviceId: serviceId)
    return .init(client: client)
}

func makeApiWebSocket(credential: String, token: String) -> ApiWebSocket {
    let client = makeApiClient(credential: credential, token: token)
    return .init(client: client)
}

#if !canImport(Darwin) || os(macOS)

func isTCPPortOpen(_ port: Int) -> Bool {
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = ["-c", "lsof -i :\(port)"]
    task.standardOutput = pipe
    task.standardError = pipe
    do { try task.run() } catch { return false }
    task.waitUntilExit()
    return task.terminationStatus == 0
}

#else

import Network
import NIOConcurrencyHelpers

func isTCPPortOpen(_ port: Int) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    let isOpen = SendableBool()
    
    guard
        port <= UInt16.max,
        port >= UInt16.min,
        let port = NWEndpoint.Port(rawValue: UInt16(port))
    else { return false }
    
    let connection = NWConnection(
        host: NWEndpoint.Host("localhost"),
        port: port,
        using: .tcp
    )

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            isOpen.bool = true
            connection.cancel()
            semaphore.signal()

        case .failed(_), .cancelled:
            isOpen.bool = false
            semaphore.signal()

        default:
            break
        }
    }

    connection.start(queue: .global())
    _ = semaphore.wait(timeout: .now() + 2)

    return isOpen.bool
}

final class SendableBool: @unchecked Sendable {
    public var bool: Bool {
        get { lock.withLock { __bool } }
        set { lock.withLock { __bool = newValue } }
    }
    private var __bool: Bool
    private let lock = NIOLock()
    
    init(_ bool: Bool = false) {
        self.__bool = bool
    }
}

#endif

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
    
    func add(_ int: Int) { value += int }
    
    var isLast: Bool { value == max }
}


actor Verifier {
    private(set) var isFullFill = false
    func fullFill() { isFullFill = true }
}
