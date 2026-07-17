import Testing
import Foundation
@testable import WhooshingServer

@Suite("Api HTTP 当传输遇到错误的处理测试集", .serialized)
struct ApiErrorTests {
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .apiError {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    let testString = "ErrorTesting"
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    let wrongCredentialClient = makeApiClient(credential: TestingShared.wrongApiClientCredential, token: TestingShared.apiClientTokenStr)
    let randomCredentialClient = makeApiClient(credential: Self.randomData(size: 16).data.base64String(), token: TestingShared.apiClientTokenStr)
    let wrongTokenClient = makeApiClient(credential: TestingShared.wrongApiClientCredential, token: TestingShared.wrongApiClientTokenStr)
    
    @Test("连线失败", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func connectionFailedTest(method: HTTPMethod) async throws {
        await #expect(throws: ApiClient.Failure.self, performing: { try await client.send(method, to: "http://localhost:1000000/") })
    }
    
    @Test("用户 credential 错误")
    func credentialInvalidTest() async throws {
        await #expect(throws: ApiClient.Failure.self, performing: { try await wrongCredentialClient.get("http://localhost:\(TestingShared.apiListenPort)/string-echo?value=\(testString)") })
    }
    
    @Test("用户 credential 错误 2")
    func credentialInvalidTest2() async throws {
        await #expect(throws: ApiClient.Failure.self, performing: { try await randomCredentialClient.get("http://localhost:\(TestingShared.apiListenPort)/string-echo?value=\(testString)") })
    }
    
    @Test("用户 token 错误")
    func tokenInvalidTest() async throws {
        await #expect(throws: ApiClient.Failure.self, performing: { try await wrongTokenClient.get("http://localhost:\(TestingShared.apiListenPort)/string-echo?value=\(testString)") })
    }
    
    @Test("404-未找到", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func errorCode404Test(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.apiListenPort)/not-exist?value=\(testString)")
        #expect(res.status == .notFound)
    }
    
    @Test("400-Get Query 必须但不存在")
    func errorCode400Test() async throws {
        var res = try await client.get("http://localhost:\(TestingShared.apiListenPort)/string-echo")
        #expect(res.status == .badRequest)
        res = try await client.get("http://localhost:\(TestingShared.apiListenPort)/string-echo?wrongquery=hello")
        #expect(res.status == .badRequest)
    }
    
    @Test("415-Send 请求体数据不合法", arguments: [HTTPMethod.POST, .PATCH, .PUT, .DELETE])
    func errorCode415Test(method: HTTPMethod) async throws {
        for i in 0..<30 {
            let res = try await client.send(method, to: "http://localhost:\(TestingShared.apiListenPort)/string-echo", headers: ["Authorization": String(i)])
            #expect(res.status == .unsupportedMediaType)
        }
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
        print("Suite \(TestingShared.testStage) 测试结束，正在关闭 Client")
        try await client.shutdown()
        try await wrongCredentialClient.shutdown()
        try await randomCredentialClient.shutdown()
        try await wrongTokenClient.shutdown()
        TestingShared.testStage = .init(rawValue: TestingShared.testStage.rawValue + 1)!
    }
}
