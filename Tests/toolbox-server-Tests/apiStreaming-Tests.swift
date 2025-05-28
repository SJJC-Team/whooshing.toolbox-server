import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import AsyncAlgorithms
import WhooshingClient

@Suite("Api 流网络通讯测试集", .enabled(if: TestingShared.apiServiceListening))
struct ApiStreamingTests {
    
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    @Test("Send stream 流请求测试", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func sendStreamingTest(method: HTTPMethod) async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            for i in 0..<10 {
                let data = Self.randomData(size: 1024)
                storage[i] = data
                print("\(i): writing")
                await stream.send(data)
            }
            stream.finish()
        }
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.apiListenPort)/streaming-echo", body: .stream(stream))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print(progress)
            #expect(storage[progress.index] == chunk)
            storage[progress.index] = nil
        }
        
        let channel = try #require(res.channel)
        try await channel.close()
        #expect(storage.isEmpty)
    }
    
    @Test("Send stream 流请求抛错测试")
    func sendStreamingThrowingTest() async throws {
        let error = Abort(.init(statusCode: 1111, reasonPhrase: "Testing"))
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        stream.fail(error)
        await #expect(throws: Abort.self, performing: {
            try await client.post("http://localhost:\(TestingShared.apiListenPort)/streaming-echo", body: .stream(stream))
        })
    }
    
    @Test("Post stream 流大数据请求测试")
    func sendLargeStreamingTest() async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            for i in 0..<100 {
                let data = Self.randomData(size: 65535)
                storage[i] = data
                print("\(i): writing")
                await stream.send(data)
            }
            stream.finish()
        }
        let res = try await client.post("http://localhost:\(TestingShared.apiListenPort)/streaming-echo", body: .stream(stream))
        #expect(res.status == .ok)
        let body = try #require(res.body)
        let bodyStream = try body.stream()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print(progress)
            #expect(storage[progress.index] == chunk)
            storage[progress.index] = nil
        }
        
        let channel = try #require(res.channel)
        try await channel.close()
        #expect(storage.isEmpty)
    }
    
    static func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var rng = SystemRandomNumberGenerator()
        let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
        buffer.writeBytes(randomBytes)
        return buffer
    }
}
