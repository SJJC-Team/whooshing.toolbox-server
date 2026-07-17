import Testing
import Foundation
@testable import WhooshingServer

@Suite("Api 文件传输测试集", .serialized)
struct ApiFileTests {
    
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .apiFile {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    @Test("Send 大量(500)多线程文件流传输")
    func fileSendTest() async throws {
        let url = FilePath(TestingShared.normalFilePath)
        let info = try #require(await FileSystem.shared.info(forFileAt: url))
        
        let threadCount = 500
        
        let collector = NumberCollector(total: threadCount)
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<threadCount {
                group.addTask {
                    var size = 0
                    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
                    
                    let res = try await client.post("http://localhost:\(TestingShared.apiListenPort)/file-echo", body: .file(from: url, progress: .init { _ in
//                         print("W(\(i))-\(ctx.index)", terminator: " ")
                    }))
                    #expect(res.status == .ok)
                    
                    let body = try #require(res.body)
                    let bodyStream = try body.stream().get()
                    
                    for try await (_, chunk) in bodyStream.withProgress() {
//                         print("R(\(i))-\(progress.index)", terminator: " ")
                        size += chunk.readableBytes
                    }
                    
                    let channel = try #require(res.channel)
                    #expect(size == info.size)
                    try await channel.close()
                    
                    await collector.done(index: i)
//                    await print("线程 \(i) 完成: \(collector.current):\(collector.total)")
                    await print("%\(collector.percentage.formatted(.number.precision(.fractionLength(1))))", terminator: " ")
                }
            }
            
            try await group.waitForAll()
        }
        
        print()
        await #expect(collector.allFinished)
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
        let res = try await client.post("http://localhost:\(TestingShared.apiListenPort)/file-echo", body: .file(from: url, progress: progress))
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

actor NumberCollector {
    let total: Int
    var current: Int
    
    func done(index: Int) {
        current += 1
    }
    
    var allFinished: Bool {
        current == total
    }
    
    var percentage: Double {
        Double(current) / Double(total) * 100
    }
    
    init(total: Int, current: Int = 0) {
        self.total = total
        self.current = current
    }
}
