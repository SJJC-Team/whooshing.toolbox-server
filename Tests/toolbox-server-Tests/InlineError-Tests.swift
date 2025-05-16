import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem
import NIOPosix
import ErrorHandle

@Suite("Whooshing Inline HTTP 当传输遇到错误的处理测试集")
struct InlineErrorTests {
    
    let testString = "ErrorTesting"
    let client = InlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    let wrongRootKeyClient = InlineClient(rootKey: TestingShared.wrongRootKey, serviceId: TestingShared.serviceIds[1])
    let wrongServiceIdClient = InlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[0])
    let randomServiceIdClient = InlineClient(rootKey: TestingShared.rootKey, serviceId: UUID())
    
    @Test("连线失败", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func connectionFailedTest(method: HTTPMethod) async throws {
        await #expect(throws: NIOConnectionError.self, performing: { try await client.send(method, to: "http://localhost:1000000/") })
    }
    
    @Test("请求服务 ID 错误")
    func serviceIDInvalidTest() async throws {
        await #expect(throws: HTTPResponseError.self, performing: { try await wrongServiceIdClient.get("http://localhost:6500/string-echo?value=\(testString)") })
    }
    
    @Test("请求服务 ID 错误 2")
    func serviceIDInvalidTest2() async throws {
        await #expect(throws: HTTPResponseError.self, performing: { try await randomServiceIdClient.get("http://localhost:6500/string-echo?value=\(testString)") })
    }
    
    @Test("RootKey 错误")
    func rootKeyInvalidTest() async throws {
        await #expect(throws: HTTPResponseError.self, performing: { try await wrongRootKeyClient.get("http://localhost:6500/string-echo?value=\(testString)") })
    }
    
    @Test("404-未找到", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func errorCode404Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:6500/not-exist?value=\(testString)")
        #expect(res.status == .notFound)
    }
    
    @Test("400-Get Query 必须但不存在")
    func errorCode400Test() async throws {
        var res = try await client.get("http://localhost:6500/string-echo")
        #expect(res.status == .badRequest)
        res = try await client.get("http://localhost:6500/string-echo?wrongquery=hello")
        #expect(res.status == .badRequest)
    }
    
    @Test("415-Send 请求体数据不合法", arguments: [HTTPMethod.POST, .PATCH, .PUT, .DELETE])
    func errorCode415Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:6500/string-echo")
        #expect(res.status == .unsupportedMediaType)
    }
    
    @Test("Stream 流大小不正确", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func streamWrongBodySizeTest(method: HTTPMethod) async throws {
        await #expect(throws: BscError.self, performing: {
            try await client.streamSend(method, to: "http://localhost:6500/stream-echo", bodySize: 1000) { request, channel, maxChunk, currentIndex in
                randomData(size: 10000)
            }
        })
    }
    
    func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var randomBytes = [UInt8](repeating: 0, count: size)
        _ = SecRandomCopyBytes(kSecRandomDefault, size, &randomBytes)
        buffer.writeBytes(randomBytes)
        return buffer
    }
}
