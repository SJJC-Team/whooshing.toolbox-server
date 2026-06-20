import Testing
import Foundation
@testable import WhooshingServer

@Suite("Inline 文件传输测试集", .serialized)
struct InlineFileTests {
    
    let client = makeInlineClient(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .inlineFile {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("Send 文件流传输", .serialized, arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func fileSendTest(method: HTTPMethod) async throws {
        for _ in 0...100 {
            var size = 0
            let url = FilePath(TestingShared.normalFilePath)
            let info = try #require(await FileSystem.shared.info(forFileAt: url))
            let res = try await client.send(method, to: "http://localhost:\(TestingShared.inlineListenPort)/file-echo", body: .file(from: url, progress: .init { _ in
                // print("W-\(ctx.index)", terminator: " ")
            }))
            #expect(res.status == .ok)
            
            let body = try #require(res.body)
            let bodyStream = try body.stream().get()
            
            for try await (_, chunk) in bodyStream.withProgress() {
                // print("R-\(progress.index)", terminator: " ")
                size += chunk.readableBytes
            }
            
            let channel = try #require(res.channel)
            #expect(size == info.size)
            try await channel.close()
        }
    }
    
    @Test("Send 大文件流传输")
    func largeFilePostTest() async throws {
        var size = 0
        let url = FilePath(TestingShared.largeFilePath)
        let info = try #require(await FileSystem.shared.info(forFileAt: url))
        let progress = AsyncProgress()
        Task {
            for try await _ in progress {
                // print("W-\(ctx.index)", terminator: " ")
            }
        }
        let res = try await client.post("http://localhost:\(TestingShared.inlineListenPort)/file-echo", body: .file(from: url, progress: progress))
        #expect(res.status == .ok)
        
        let body = try #require(res.body)
        let bodyStream = try body.stream().get()
        
        for try await (_, chunk) in bodyStream.withProgress() {
            // print("R-\(progress.index)", terminator: " ")
            size += chunk.readableBytes
        }
        
        let channel = try #require(res.channel)
        #expect(size == info.size)
        print(info.size)
        try await channel.close()
    }
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        print("Suite \(TestingShared.testStage) 测试结束，正在关闭 Client")
        try await client.shutdown()
        TestingShared.testStage = .init(rawValue: TestingShared.testStage.rawValue + 1)!
    }
}
