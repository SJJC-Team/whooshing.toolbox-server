import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient

@Suite("Inline 基本网络通讯测试集", .serialized)
struct InlineNormalTests {
    
    let testString = "Hello World!"
    
    let client = makeInlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .inlineNormal {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("HTTP send zero body 请求测试", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func sendZeroBodyRequestTest(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.inlineListenPort)/no-body")
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == "NO-BODY".lengthOfBytes(using: .utf8))
        #expect(try res.body?.text().get() == "NO-BODY")
    }
    
    @Test("HTTP send 请求测试", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func sendRequestTest(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.inlineListenPort)/string-echo?value=\(testString)", body: .text(testString).get())
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == testString.lengthOfBytes(using: .utf8))
        #expect(try res.body?.text().get() == testString)
    }
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        try await client.shutdown()
        TestingShared.testStage = .init(rawValue: TestingShared.testStage.rawValue + 1)!
    }
}
