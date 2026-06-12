import Cryptos
import Foundation
import NIO
import Logging
import LoggingAdvanced
import WhooshingClient
import WhooshingWebSocket
import NIOConcurrencyHelpers
@testable import WhooshingServer

struct TestingShared {
    enum TestStage: Int {
        case serverPrepare
        case enviromentParsing
        case driverEnvParsing
        case httpsError
        case httpsFile
        case httpsNormal
        case httpsStreaming
        case httpsWebSocket
        case apiError
        case apiFile
        case apiNormal
        case apiStreaming
        case apiWebSocket
        case inlineError
        case inlineFile
        case inlineNormal
        case inlineStreaming
        case inlineWebSocket
        case done
    }
    
    @MainActor static var testStage: TestStage = .serverPrepare
    
    static let rootKey = SendableSymmKey(key: .init(data: Data(base64Encoded: rootKeyStr)!))
    static let rootKeyStr = "0apYyvRtLuo7l07zuqbEjFIxDFZ1sIWabKM9mMOOIzQ="
    
    static let wrongRootKey = SendableSymmKey(key: .init(data: Data(base64Encoded: wrongRootKeyStr)!))
    static let wrongRootKeyStr = "Mzn/h5zDnIdi4C3yHaRMG62DhC9qYt8q4SfOCV338hY="
    
    static let apiClientCredential = "bRRPIiYbt0t4RzfqeeHSkg=="
    
    static let wrongApiClientCredential = "PXt3S3oMWfHIE7wb1S1nMg=="
    
    static let apiClientToken = SendableSymmKey(key: .init(data: Data(base64Encoded: apiClientTokenStr)!))
    static let apiClientTokenStr = "jXTz4vTQk0O/XFIjWQIHLC7z9/E0/4VtEb+LkF8IcA4="
    
    static let wrongApiClientToken = SendableSymmKey(key: .init(data: Data(base64Encoded: wrongApiClientTokenStr)!))
    static let wrongApiClientTokenStr = "9cCat+omad2WPRetG0VdqSdVhBPVz5kXJ2DssJtQshI="
    
    static let inlineListenPort = 6500
    static let httpsListenPort = 6501
    static let apiListenPort = 6502
    
    static let testingPaths = FilePreparePaths(
        small: "./testing_files/test.png",
        large: "./testing_files/large.zip",
        smallSize: 3 * 1024 * 1024, // 3M
        largeSize: 1 * 1024 * 1024 * 1024, // 1G
        smallChunk: 1 * 1024 * 1024,
        largeChunk: 1 * 1024 * 1024
    )
    
    nonisolated(unsafe) static var normalFilePath: String!
    static let normalFileName = "test.png"
    nonisolated(unsafe) static var largeFilePath: String!
    static let largeFileName = "large.zip"
    
    static let serviceIds = [
        UUID(uuidString: "F1ECC1D7-6E19-4F50-9B89-68FAA332B415")!,
        UUID(uuidString: "2AC424F7-F26A-4EA4-BE44-202ABC7CC514")!,
        UUID(uuidString: "74854475-1C1A-48E2-BAC9-E9C752942F88")!,
    ]
    
    static let logLevel = Logger.Level.notice
    
    static var initLoggingSystem: Bool {
        get { lock.withLock { __initLoggingSystem } }
        set { lock.withLock { __initLoggingSystem = newValue } }
    }
    nonisolated(unsafe) private static var __initLoggingSystem = false
    private static let lock = NIOLock()
    
    static let loggingSystem: Void = {
        var factory = LoggingFactory()
        factory.add("Console")
        factory.bootstrap()
    }()
}

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 30)

func initLoggingSystemIfNot() {
    if !TestingShared.initLoggingSystem {
        _ = TestingShared.loggingSystem
        TestingShared.initLoggingSystem = true
    }
}

func makeHttpsClient() -> HttpsClient {
    initLoggingSystemIfNot()
    
    var logger = Logger(label: "Testing-Https")
    logger.logLevel = TestingShared.logLevel
    return HttpsClient(in: eventLoopGroup.next(), logger: logger)
}

func makeInlineClient(rootKey: SendableSymmKey, serviceId: UUID) -> InlineClient {
    initLoggingSystemIfNot()
    
    var logger = Logger(label: "Testing-Inline")
    logger.logLevel = TestingShared.logLevel
    let client = InlineClient(eventLoop: eventLoopGroup.next(), logger: logger, byteBufferAllocator: .init())
    let ioHandler = Inline.RequestIOCrypto(client: client)
    client.ioHandler = ioHandler
    client.storage[Inline.RequestIOData.self] = .init(rootKey: rootKey, serviceID: serviceId)
    return client
}

func makeApiClient(credential: String, token: String) -> ApiClient {
    initLoggingSystemIfNot()
    
    var logger = Logger(label: "Testing-Api")
    logger.logLevel = TestingShared.logLevel
    return ApiClient(credential: credential, token: token, eventLoop: eventLoopGroup.next(), logger: logger)
}

func makeHttpsWebSocket() -> HttpsWebSocket {
    let logger = Logger(label: "Testing-HTTPS")
    return HttpsWebSocket(in: eventLoopGroup.next(), logger: logger)
}

func makeInlineWebSocket(rootKey: SendableSymmKey, serviceId: UUID) -> InlineWebSocket {
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
