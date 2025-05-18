import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient

@Suite("Https 流网络通讯测试集", .enabled(if: TestingShared.httpsServiceListening))
struct HttpsStreamingTests {
    
    let client = makeHttpsClient()
    
    @Test("Send stream 流请求测试", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func sendStreamingTest(method: HTTPMethod) async throws {
        let totalSize = 10000
        let verify = Verifier()
        let counter = Counter(max: totalSize)
        let res = try await client.streamSend(method, to: "http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", bodySize: totalSize, stream: { request, maxChunk, currentIndex in
            let data = Self.randomData(size: min(totalSize - (currentIndex * maxChunk), maxChunk))
            return data
        }, progress: { progress in
            print(progress)
            if let res = progress.response {
                #expect(res.status == .ok)
                if progress.index >= 0 {
                    Task { await counter.add(progress.data.readableBytes) }
                }
                if progress.done {
                    Task { await verify.fullFill() }
                    #expect(progress.curBytes == totalSize)
                }
            }
        })
        #expect(await verify.isFullFill)
        #expect(await counter.value == totalSize)
        #expect(res.status == .ok)
        #expect(res.body == nil)
    }
    
    @Test("Send stream 流请求抛错测试")
    func sendStreamingThrowingTest() async throws {
        let totalSize = 10000
        let error = Abort(.init(statusCode: 1111, reasonPhrase: "Testing"))
        await #expect(throws: Abort.self, performing: {
            try await client.streamPost("http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", bodySize: totalSize, stream: { request, maxChunk, currentIndex in
                throw error
            })
        })
    }
    
    @Test("Send async stream 流请求测试", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func asyncSendStreamingTest(method: HTTPMethod) async throws {
        let totalSize = 10000
        let verify = Verifier()
        let counter = Counter(max: totalSize)
        let res = try await client.asyncStreamSend(method, to: "http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", bodySize: totalSize, stream: { request, eventLoop, maxChunk, currentIndex in
            let data = Self.randomData(size: min(totalSize - (currentIndex * maxChunk), maxChunk))
            return eventLoop.makeSucceededFuture(data)
        }, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index >= 0 {
                    print("read i: \(progress.index)")
                    Task { await counter.add(progress.data.readableBytes) }
                    #expect(res.status == .ok)
                }
                if progress.done {
                    Task { await verify.fullFill() }
                    #expect(progress.curBytes == totalSize)
                }
            }
        }).get()
        #expect(await verify.isFullFill)
        #expect(await counter.value == totalSize)
        #expect(res.status == .ok)
        #expect(res.body == nil)
    }
    
    @Test("Post stream 流大数据请求测试")
    func sendLargeStreamingTest() async throws {
        let totalSize = 10000000
        let verify = Verifier()
        let counter = Counter(max: totalSize)
        let res = try await client.streamPost("http://localhost:\(TestingShared.httpsListenPort)/streaming-echo", bodySize: totalSize, stream: { request, maxChunk, currentIndex in
            let data = Self.randomData(size: min(totalSize - (currentIndex * maxChunk), maxChunk))
            return data
        }, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index >= 0 {
                    print("read i: \(progress.index)")
                    Task { await counter.add(progress.data.readableBytes) }
                    #expect(res.status == .ok)
                }
                if progress.done {
                    Task { await verify.fullFill() }
                    #expect(progress.curBytes == totalSize)
                }
            }
        })
        #expect(await verify.isFullFill)
        #expect(await counter.value == totalSize)
        #expect(res.status == .ok)
        #expect(res.body == nil)
    }
    
    static func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var rng = SystemRandomNumberGenerator()
        let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
        buffer.writeBytes(randomBytes)
        return buffer
    }
}
