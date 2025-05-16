import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem
import NIOPosix
import ErrorHandle

@Suite("Api HTTP 当传输遇到错误的处理测试集")
struct ApiErrorTests {
    
    let testString = "ErrorTesting"
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    let wrongCredentialClient = makeApiClient(credential: TestingShared.wrongApiClientCredential, token: TestingShared.apiClientTokenStr)
    let randomCredentialClient = makeApiClient(credential: Self.randomData(size: 16).data().base64String(), token: TestingShared.apiClientTokenStr)
    let wrongTokenClient = makeApiClient(credential: TestingShared.wrongApiClientCredential, token: TestingShared.wrongApiClientTokenStr)
    
    @Test("连线失败", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func connectionFailedTest(method: HTTPMethod) async throws {
        await #expect(throws: NIOConnectionError.self, performing: { try await client.send(method, to: "http://localhost:1000000/") })
    }
    
    @Test("用户 credential 错误")
    func credentialInvalidTest() async throws {
        await #expect(throws: HTTPResponseError.self, performing: { try await wrongCredentialClient.get("http://localhost:6502/string-echo?value=\(testString)") })
    }
    
    @Test("用户 credential 错误 2")
    func credentialInvalidTest2() async throws {
        await #expect(throws: HTTPResponseError.self, performing: { try await randomCredentialClient.get("http://localhost:6502/string-echo?value=\(testString)") })
    }
    
    @Test("用户 token 错误")
    func tokenInvalidTest() async throws {
        await #expect(throws: HTTPResponseError.self, performing: { try await wrongTokenClient.get("http://localhost:6502/string-echo?value=\(testString)") })
    }
    
    @Test("404-未找到", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func errorCode404Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:6502/not-exist?value=\(testString)")
        #expect(res.status == .notFound)
    }
    
    @Test("400-Get Query 必须但不存在")
    func errorCode400Test() async throws {
        var res = try await client.get("http://localhost:6502/string-echo")
        #expect(res.status == .badRequest)
        res = try await client.get("http://localhost:6502/string-echo?wrongquery=hello")
        #expect(res.status == .badRequest)
    }
    
    @Test("415-Send 请求体数据不合法", arguments: [HTTPMethod.POST, .PATCH, .PUT, .DELETE])
    func errorCode415Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:6502/string-echo")
        #expect(res.status == .unsupportedMediaType)
    }
    
    @Test("Stream 流大小不正确", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func streamWrongBodySizeTest(method: HTTPMethod) async throws {
        await #expect(throws: BscError.self, performing: {
            try await client.streamSend(method, to: "http://localhost:6502/stream-echo", bodySize: 1000) { request, channel, maxChunk, currentIndex in
                Self.randomData(size: 10000)
            }
        })
    }
    
    static func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var randomBytes = [UInt8](repeating: 0, count: size)
        _ = SecRandomCopyBytes(kSecRandomDefault, size, &randomBytes)
        buffer.writeBytes(randomBytes)
        return buffer
    }
}
