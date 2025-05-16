import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient

@Suite("Whooshing 基本网络通讯测试集")
struct HTTPNormalTests {
    
    let testString = "Hello World!"
    
    let client = InlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    @Test("HTTP send 请求测试", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func sendRequestTest(method: HTTPMethod) async throws {
        let res = try await client.send(method, to: "http://localhost:6500/string-echo?value=\(testString)") { req, _ in
            try req.bodyEncode(testString, as: HTTPBody.text)
        }
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == testString.lengthOfBytes(using: .utf8))
        #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
    }
    
    @Test("HTTP async send 请求测试", arguments: [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE])
    func asyncSendRequestTest(method: HTTPMethod) async throws {
        try await client.asyncSend(method, to: "http://localhost:6500/string-echo?value=\(testString)") { req, _ in
            try req.bodyEncode(testString, as: HTTPBody.text)
        }.flatMapThrowing { res in
            #expect(res.status == .ok)
            #expect(res.headers.contains(name: "content-length"))
            let length = try Int(#require(res.headers.first(name: "content-length")))
            #expect(length == testString.lengthOfBytes(using: .utf8))
            #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
        }.get()
    }
    
    @Test("HTTP post generic 请求测试")
    func postGenericRequestTest() async throws {
        let res = try await client.post("http://localhost:6500/string-echo", content: testString, type: HTTPBody.text)
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == testString.lengthOfBytes(using: .utf8))
        #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
    }
    
    @Test("HTTP patch generic 请求测试")
    func patchGenericRequestTest() async throws {
        let res = try await client.patch("http://localhost:6500/string-echo", content: testString, type: HTTPBody.text)
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == testString.lengthOfBytes(using: .utf8))
        #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
    }
    
    @Test("HTTP put generic 请求测试")
    func putGenericRequestTest() async throws {
        let res = try await client.put("http://localhost:6500/string-echo", content: testString, type: HTTPBody.text)
        #expect(res.status == .ok)
        #expect(res.headers.contains(name: "content-length"))
        let length = try Int(#require(res.headers.first(name: "content-length")))
        #expect(length == testString.lengthOfBytes(using: .utf8))
        #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
    }
    
    @Test("HTTP async post generic 请求测试")
    func asyncPostGenericRequestTest() async throws {
        try await client.asyncPost("http://localhost:6500/string-echo", content: testString, type: HTTPBody.text).flatMapThrowing { res in
            #expect(res.status == .ok)
            #expect(res.headers.contains(name: "content-length"))
            let length = try Int(#require(res.headers.first(name: "content-length")))
            #expect(length == testString.lengthOfBytes(using: .utf8))
            #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
        }.get()
    }
    
    @Test("HTTP async patch generic 请求测试")
    func asyncPatchGenericRequestTest() async throws {
        try await client.asyncPatch("http://localhost:6500/string-echo", content: testString, type: HTTPBody.text).flatMapThrowing { res in
            #expect(res.status == .ok)
            #expect(res.headers.contains(name: "content-length"))
            let length = try Int(#require(res.headers.first(name: "content-length")))
            #expect(length == testString.lengthOfBytes(using: .utf8))
            #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
        }.get()
    }
    
    @Test("HTTP async put generic 请求测试")
    func asyncPutGenericRequestTest() async throws {
        try await client.asyncPut("http://localhost:6500/string-echo", content: testString, type: HTTPBody.text).flatMapThrowing { res in
            #expect(res.status == .ok)
            #expect(res.headers.contains(name: "content-length"))
            let length = try Int(#require(res.headers.first(name: "content-length")))
            #expect(length == testString.lengthOfBytes(using: .utf8))
            #expect(try res.bodyDecode(to: HTTPBody.text.self) == testString)
        }.get()
    }
    
}
