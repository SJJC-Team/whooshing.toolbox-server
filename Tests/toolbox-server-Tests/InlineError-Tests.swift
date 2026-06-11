import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem
import NIOPosix
import ErrorHandle

@Suite("Inline HTTP 当传输遇到错误的处理测试集", .serialized)
struct InlineErrorTests {
    
    let testString = "ErrorTesting"
    let client = makeInlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    let wrongRootKeyClient = makeInlineClient(rootKey: TestingShared.wrongRootKey, serviceId: TestingShared.serviceIds[1])
    let wrongServiceIdClient = makeInlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[0])
    let randomServiceIdClient = makeInlineClient(rootKey: TestingShared.rootKey, serviceId: UUID())
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .inlineError {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("连线失败", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func connectionFailedTest(method: HTTPMethod) async throws {
        await #expect(throws: InlineClient.Failure.self, performing: { try await client.send(method, to: "http://localhost:1000000/") })
    }
    
    @Test("请求服务 ID 错误")
    func serviceIDInvalidTest() async throws {
        await #expect(throws: InlineClient.Failure.self, performing: { try await wrongServiceIdClient.get("http://localhost:\(TestingShared.inlineListenPort)/string-echo?value=\(testString)") })
    }
    
    @Test("请求服务 ID 错误 2")
    func serviceIDInvalidTest2() async throws {
        await #expect(throws: InlineClient.Failure.self, performing: { try await randomServiceIdClient.get("http://localhost:\(TestingShared.inlineListenPort)/string-echo?value=\(testString)") })
    }
    
    @Test("RootKey 错误")
    func rootKeyInvalidTest() async throws {
        await #expect(throws: InlineClient.Failure.self, performing: { try await wrongRootKeyClient.get("http://localhost:\(TestingShared.inlineListenPort)/string-echo?value=\(testString)") })
    }
    
    @Test("404-未找到", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func errorCode404Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.inlineListenPort)/not-exist?value=\(testString)")
        #expect(res.status == .notFound)
    }
    
    @Test("400-Get Query 必须但不存在")
    func errorCode400Test() async throws {
        var res = try await client.get("http://localhost:\(TestingShared.inlineListenPort)/string-echo")
        #expect(res.status == .badRequest)
        res = try await client.get("http://localhost:\(TestingShared.inlineListenPort)/string-echo?wrongquery=hello")
        #expect(res.status == .badRequest)
    }
    
    @Test("415-Send 请求体数据不合法", arguments: [HTTPMethod.POST, .PATCH, .PUT, .DELETE])
    func errorCode415Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.inlineListenPort)/string-echo")
        #expect(res.status == .unsupportedMediaType)
    }
    
    static func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var rng = SystemRandomNumberGenerator()
        let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
        buffer.writeBytes(randomBytes)
        return buffer
    }
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        try await client.shutdown()
        TestingShared.testStage = .init(rawValue: TestingShared.testStage.rawValue + 1)!
    }
}
