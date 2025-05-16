import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient

@Suite("Api 流网络通讯测试集", .enabled(if: TestingShared.apiServiceListening))
struct ApiStreamingTests {
    
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    @Test("Send stream 流请求测试", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func sendStreamingTest(method: HTTPMethod) async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let totalSize = 10000
        try await client.streamSend(method, to: "http://localhost:\(TestingShared.apiListenPort)/streaming-echo", bodySize: totalSize, stream: { request, channel, maxChunk, currentIndex in
            let data = Self.randomData(size: min(totalSize - (currentIndex * maxChunk), maxChunk))
            storage[currentIndex] = data
            return data
        }, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index >= 0 {
                    #expect(res.status == .ok)
                    let origin = try #require(storage[progress.index])
                    #expect(origin == progress.data)
                    storage[progress.index] = nil
                } else {
                    #expect(res.headers.first(name: .contentLength) == String(totalSize))
                }
            }
        })
        #expect(storage.isEmpty)
    }
    
    @Test("Send async stream 流请求测试", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func asyncSendStreamingTest(method: HTTPMethod) async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let totalSize = 10000
        try await client.asyncStreamSend(method, to: "http://localhost:\(TestingShared.apiListenPort)/streaming-echo", bodySize: totalSize, stream: { request, channel, maxChunk, currentIndex in
            let data = Self.randomData(size: min(totalSize - (currentIndex * maxChunk), maxChunk))
            storage[currentIndex] = data
            return channel.eventLoop.makeSucceededFuture(data)
        }, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index >= 0 {
                    #expect(res.status == .ok)
                    let origin = try #require(storage[progress.index])
                    #expect(origin == progress.data)
                    storage[progress.index] = nil
                } else {
                    #expect(res.headers.first(name: .contentLength) == String(totalSize))
                }
            }
        }).get()
        #expect(storage.isEmpty)
    }
    
    @Test("Send stream 流请求抛错测试")
    func sendStreamingThrowingTest() async throws {
        let totalSize = 10000
        let error = Abort(.init(statusCode: 1111, reasonPhrase: "Testing"))
        await #expect(throws: Abort.self, performing: {
            try await client.streamPost("http://localhost:\(TestingShared.apiListenPort)/streaming-echo", bodySize: totalSize, stream: { request, channel, maxChunk, currentIndex in
                throw error
            })
        })
    }
    
    @Test("Post stream 流大数据请求测试")
    func sendLargeStreamingTest() async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let totalSize = 1000000
        try await client.streamPost("http://localhost:\(TestingShared.apiListenPort)/streaming-echo", bodySize: totalSize, stream: { request, channel, maxChunk, currentIndex in
            let data = Self.randomData(size: min(totalSize - (currentIndex * maxChunk), maxChunk))
            storage[currentIndex] = data
            return data
        }, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index >= 0 {
                    #expect(res.status == .ok)
                    let origin = try #require(storage[progress.index])
                    #expect(origin == progress.data)
                    storage[progress.index] = nil
                } else {
                    #expect(res.headers.first(name: .contentLength) == String(totalSize))
                }
            }
        })
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
