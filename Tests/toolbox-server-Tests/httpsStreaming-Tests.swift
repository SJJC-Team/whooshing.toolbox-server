import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import AsyncAlgorithms

@Suite("Https 流网络通讯测试集", .serialized)
struct HttpsStreamingTests {
    
    let client = makeHttpsClient()
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .httpsStreaming {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("Send stream 流请求测试", arguments: [HTTPMethod.POST])
    func sendStreamingTest(method: HTTPMethod) async throws {
        var size = 0
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            for ctx in Progress(pieces: 10, chunk: 1024) {
                print("写入中: \(ctx)")
                let data = Self.randomData(size: ctx.bytes)
                await stream.send(data)
            }
            stream.finish()
        }
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", body: .stream(stream))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print(progress)
            size += chunk.readableBytes
        }
        
        #expect(size == 10240)
    }
    
    @Test("Send stream 流请求抛错测试")
    func sendStreamingThrowingTest() async throws {
        let error = Abort(.init(statusCode: 1111, reasonPhrase: "Testing"))
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        stream.fail(error)
        await #expect(throws: HttpsClient.Failure.self, performing: {
            try await client.post("http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", body: .stream(stream))
        })
    }
    
    @Test("Post stream 流大数据请求测试")
    func sendLargeStreamingTest() async throws {
        var size = 0
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            for ctx in Progress(pieces: 100, chunk: 65535) {
                print("写入中: \(ctx)")
                let data = Self.randomData(size: ctx.bytes)
                await stream.send(data)
            }
            stream.finish()
        }
        let res = try await client.post("http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", body: .stream(stream))
        #expect(res.status == .ok)
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print(progress)
            size += chunk.readableBytes
        }
        
        #expect(size == 6553500)
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
