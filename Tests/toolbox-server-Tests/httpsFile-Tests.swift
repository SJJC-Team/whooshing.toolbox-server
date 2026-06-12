import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem

@Suite("Https 文件传输测试集", .serialized)
struct HttpsFileTests {
    
    let client = makeHttpsClient()
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .httpsFile {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("创建测试文件")
    func testFileCreating() async throws {
        let res = try await client.post("http://localhost:\(TestingShared.httpsListenPort)/file-prepare", body: .json(TestingShared.testingPaths).get())
        let body = try #require(res.body)
        let paths = try body.json(as: FilePrepareRes.self).get()
        TestingShared.normalFilePath = paths.smallPath
        TestingShared.largeFilePath = paths.largetPath
    }
    
    @Test("Send 文件流传输", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func fileSendTest(method: HTTPMethod) async throws {
        var size = 0
        let url = FilePath(TestingShared.normalFilePath)
        let info = try #require(await FileSystem.shared.info(forFileAt: url))
        let res = try await client.send(method, to: "http://localhost:\(TestingShared.httpsListenPort)/file-echo", body: .file(from: url, progress: .init { ctx in
            print("W-\(ctx.index)", terminator: " ")
        }))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print("R-\(progress.index)", terminator: " ")
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
                print("W-\(ctx.index)", terminator: " ")
            }
        }
        let res = try await client.post("http://localhost:\(TestingShared.httpsListenPort)/file-echo", body: .file(from: url, progress: progress))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (progress, chunk) in bodyStream.withProgress() {
            print("R-\(progress.index)", terminator: " ")
            size += chunk.readableBytes
        }
        
        #expect(size == info.size)
    }
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        print("Suite \(TestingShared.testStage) 测试结束，正在关闭 Client")
        try await client.shutdown()
        TestingShared.testStage = .init(rawValue: TestingShared.testStage.rawValue + 1)!
    }
}
