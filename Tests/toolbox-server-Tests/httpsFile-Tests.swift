import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem

@Suite("Https 文件传输测试集", .enabled(if: TestingShared.httpsServiceListening))
struct HttpsFileTests {
    
    let client = makeHttpsClient()
    
    @Test("Send 文件流传输", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func fileSendTest(method: HTTPMethod) async throws {
        var size = 0
        let url = FilePath(TestingShared.normalFilePath)
        let info = try #require(await FileSystem.shared.info(forFileAt: url))
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.httpsListenPort)/file-echo", body: .file(from: url, progress: .init { ctx in
            print("写入中: \(ctx)")
        }))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print(progress)
            size += chunk.readableBytes
        }
        
        #expect(size == info.size)
    }
    
    @Test("Send 大文件流传输")
    func largeFilePostTest() async throws {
        var size = 0
        let url = FilePath(TestingShared.largeFilePath)
        let info = try #require(await FileSystem.shared.info(forFileAt: url))
        let progress = AsyncProgress()
        Task {
            for try await ctx in progress {
                print("写入中: \(ctx)")
            }
        }
        let res = try await client.post("http://localhost:\(TestingShared.httpsListenPort)/file-echo", body: .file(from: url, progress: progress))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print(progress)
            size += chunk.readableBytes
        }
        
        #expect(size == info.size)
    }
}
