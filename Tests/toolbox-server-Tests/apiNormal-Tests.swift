import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient

@Suite("Api 基本网络通讯测试集", .enabled(if: TestingShared.apiServiceListening))
struct ApiNormalTests {
    
    let testString = "Hello World!"
    
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    @Test("HTTP send zero body 请求测试", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func sendZeroBodyRequestTest(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.apiListenPort)/no-body")
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == "NO-BODY".lengthOfBytes(using: .utf8))
        #expect(try res.body?.text() == "NO-BODY")
    }
    
    @Test("HTTP send 请求测试", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func sendRequestTest(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.apiListenPort)/string-echo?value=\(testString)", body: .text(testString))
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == testString.lengthOfBytes(using: .utf8))
        #expect(try res.body?.text() == testString)
    }
}
