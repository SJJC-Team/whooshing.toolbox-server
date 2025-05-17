import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import NIOFileSystem

@Suite("Api 文件传输测试集", .enabled(if: TestingShared.apiServiceListening))
struct ApiFileTests {
    
    let client = makeApiClient(credential: TestingShared.apiClientCredential, token: TestingShared.apiClientTokenStr)
    
    @Test("Send 文件流传输", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func fileSendTest(method: HTTPMethod) async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let url = try #require(Bundle.module.url(forResource: "test", withExtension: "png"))
        let info = try #require(await FileSystem.shared.info(forFileAt: .init(url.path())))
        try await client.fileSend(method, to: "http://localhost:\(TestingShared.apiListenPort)/file-echo", file: url.path(), progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index == -1 {
                    print(res)
                    #expect(res.headers.first(name: .contentDisposition) == "test.png")
                    #expect(res.headers.first(name: .contentLength) == String(info.size))
                } else {
                    let origin = try #require(storage[progress.index])
                    #expect(origin == progress.data)
                    storage[progress.index] = nil
                }
            } else {
                if progress.index >= 0 {
                    #expect(storage[progress.index] == nil)
                    storage[progress.index] = progress.data
                }
            }
        })
        #expect(storage.isEmpty)
    }
    
    @Test("Send async 文件流传输", arguments: [HTTPMethod.POST, .PATCH, .PUT])
    func asyncFileSendTest(method: HTTPMethod) async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let url = try #require(Bundle.module.url(forResource: "test", withExtension: "png"))
        let info = try #require(await FileSystem.shared.info(forFileAt: .init(url.path())))
        try await client.asyncFileSend(method, to: "http://localhost:\(TestingShared.apiListenPort)/file-echo", file: url.path(), progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index == -1 {
                    print(res)
                    #expect(res.headers.first(name: .contentDisposition) == "test.png")
                    #expect(res.headers.first(name: .contentLength) == String(info.size))
                } else {
                    let origin = try #require(storage[progress.index])
                    #expect(origin == progress.data)
                    storage[progress.index] = nil
                }
            } else {
                if progress.index >= 0 {
                    #expect(storage[progress.index] == nil)
                    storage[progress.index] = progress.data
                }
            }
        }).get()
        #expect(storage.isEmpty)
    }
    
    @Test("Post 大文件数据流传输")
    func largeFilePostTest() async throws {
        let storage = SendableDictionary<Int, ByteBuffer>()
        let url = try #require(Bundle.module.url(forResource: "Books", withExtension: "zip"))
        let info = try #require(await FileSystem.shared.info(forFileAt: .init(url.path())))
        try await client.filePost("http://localhost:\(TestingShared.apiListenPort)/file-echo", file: url.path(), progress: { progress in
            print(progress)
            if let res = progress.response {
                if progress.index == -1 {
                    print(res)
                    #expect(res.headers.first(name: .contentDisposition) == "Books.zip")
                    #expect(res.headers.first(name: .contentLength) == String(info.size))
                } else {
                    let origin = try #require(storage[progress.index])
                    #expect(origin == progress.data)
                    storage[progress.index] = nil
                }
            } else {
                if progress.index >= 0 {
                    #expect(storage[progress.index] == nil)
                    storage[progress.index] = progress.data
                }
            }
        })
        #expect(storage.isEmpty)
    }
}
