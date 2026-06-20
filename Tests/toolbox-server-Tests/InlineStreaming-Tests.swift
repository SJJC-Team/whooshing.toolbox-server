import Testing
import Foundation
@testable import WhooshingServer

@Suite("Inline 流网络通讯测试集", .serialized)
struct InlineStreamingTests {
    
    let client = makeInlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .inlineStreaming {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("Send stream 流请求测试", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func sendStreamingTest(method: HTTPMethod) async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            for ctx in Progress(pieces: 10, chunk: 1024) {
                // print("W-\(ctx.index)", terminator: " ")
                let data = Self.randomData(size: ctx.bytes)
                storage[ctx.index] = data
                await stream.send(data)
            }
            stream.finish()
        }
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.inlineListenPort)/streaming-echo", body: .stream(stream))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            // print("R-\(progress.index)", terminator: " ")
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
        await #expect(throws: InlineClient.Failure.self, performing: {
            try await client.post("http://localhost:\(TestingShared.inlineListenPort)/streaming-echo", body: .stream(stream))
        })
    }
    
    @Test("Post stream 流大数据请求测试")
    func sendLargeStreamingTest() async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            for ctx in Progress(pieces: 100, chunk: 65535) {
                // print("W-\(ctx.index)", terminator: " ")
                let data = Self.randomData(size: ctx.bytes)
                storage[ctx.index] = data
                await stream.send(data)
            }
            stream.finish()
        }
        let res = try await client.post("http://localhost:\(TestingShared.inlineListenPort)/streaming-echo", body: .stream(stream))
        #expect(res.status == .ok)
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            // print("R-\(progress.index)", terminator: " ")
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
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        print("Suite \(TestingShared.testStage) 测试结束，正在关闭 Client")
        try await client.shutdown()
        TestingShared.testStage = .init(rawValue: TestingShared.testStage.rawValue + 1)!
    }
}
