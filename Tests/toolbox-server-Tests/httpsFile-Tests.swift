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
        let url = try #require(Bundle.module.url(forResource: "test", withExtension: "png"))
        let info = try #require(await FileSystem.shared.info(forFileAt: .init(url.relativePath)))
        let verify = Verifier()
        let counter = Counter(max: Int(info.size))
        let res = try await client.fileSend(method, to: "http://localhost:\(TestingShared.httpsListenPort)/file-echo", file: url.relativePath, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index == -1 {
                    print(res)
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: .contentDisposition) == "test.png")
                } else {
                    Task { await counter.add(progress.data.readableBytes) }
                }
                if progress.done {
                    Task { await verify.fullFill() }
                    #expect(progress.curBytes == info.size)
                }
            }
        })
        #expect(await verify.isFullFill)
        #expect(await counter.value == info.size)
        #expect(res.status == .ok)
        #expect(res.body == nil)
    }
    
    @Test("Send async 文件流传输", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func asyncFileSendTest(method: HTTPMethod) async throws {
        let url = try #require(Bundle.module.url(forResource: "test", withExtension: "png"))
        let info = try #require(await FileSystem.shared.info(forFileAt: .init(url.relativePath)))
        let verify = Verifier()
        let counter = Counter(max: Int(info.size))
        let res = try await client.asyncFileSend(method, to: "http://localhost:\(TestingShared.httpsListenPort)/file-echo", file: url.relativePath, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index == -1 {
                    print(res)
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: .contentDisposition) == "test.png")
                } else {
                    Task { await counter.add(progress.data.readableBytes) }
                }
                if progress.done {
                    Task { await verify.fullFill() }
                    #expect(progress.curBytes == info.size)
                }
            }
        }).get()
        #expect(await verify.isFullFill)
        #expect(await counter.value == info.size)
        #expect(res.status == .ok)
        #expect(res.body == nil)
    }
    
    @Test("Post 大文件数据流传输")
    func largeFilePostTest() async throws {
        let url = try #require(Bundle.module.url(forResource: "Books", withExtension: "zip"))
        let info = try #require(await FileSystem.shared.info(forFileAt: .init(url.relativePath)))
        let verify = Verifier()
        let counter = Counter(max: Int(info.size))
        let res = try await client.filePost("http://localhost:\(TestingShared.httpsListenPort)/file-echo", file: url.relativePath, progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index == -1 {
                    print(res)
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: .contentDisposition) == "Books.zip")
                } else {
                    Task { await counter.add(progress.data.readableBytes) }
                }
                if progress.done {
                    Task { await verify.fullFill() }
                    #expect(progress.curBytes == info.size)
                }
            }
        })
        #expect(await verify.isFullFill)
        #expect(await counter.value == info.size)
        #expect(res.status == .ok)
        #expect(res.body == nil)
    }
}
