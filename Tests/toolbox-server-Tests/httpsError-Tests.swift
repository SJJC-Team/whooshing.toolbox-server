import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem
import NIOPosix
import ErrorHandle

@Suite("Https HTTP 当传输遇到错误的处理测试集", .enabled(if: TestingShared.httpsServiceListening))
struct HttpsErrorTests {
    
    let testString = "ErrorTesting"
    let client = makeHttpsClient()
    
    @Test("连线失败", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func connectionFailedTest(method: HTTPMethod) async throws {
        #if !canImport(Darwin) || os(macOS)
        await #expect(throws: HttpsClient.Failure.self, performing: { try await client.send(method, to: "http://localhost:1000000/") })
        #else
        await #expect(throws: HttpsClient.Failure.self, performing: { try await client.send(method, to: "http://localhost:1000000/") })
        #endif
    }
    
    @Test("404-未找到", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func errorCode404Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.httpsListenPort)/not-exist?value=\(testString)")
        #expect(res.status == .notFound)
    }
    
    @Test("400-Get Query 必须但不存在")
    func errorCode400Test() async throws {
        var res = try await client.get("http://localhost:\(TestingShared.httpsListenPort)/string-echo")
        #expect(res.status == .badRequest)
        res = try await client.get("http://localhost:\(TestingShared.httpsListenPort)/string-echo?wrongquery=hello")
        #expect(res.status == .badRequest)
    }
    
    @Test("415-Send 请求体数据不合法", arguments: [HTTPMethod.POST, .PATCH, .PUT, .DELETE])
    func errorCode415Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.httpsListenPort)/string-echo")
        #expect(res.status == .unsupportedMediaType)
    }
    
    static func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var rng = SystemRandomNumberGenerator()
        let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
        buffer.writeBytes(randomBytes)
        return buffer
    }
}
