import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient
import WhooshingWebSocket
import NIOPosix

@Suite("Inline WebSocket 测试集", .serialized)
struct InlineWebSocketTests {
    
    let ws = makeInlineWebSocket(rootKey: TestingShared.rootKey, serviceId: TestingShared.serviceIds[1])
    
    @Test("WebSocket 数据交互", arguments: [
        (10000, "normal", 10),
        (10, "largest", ChunkTool.maxChunk - 50),
    ])
    func dataCommuteTest(paras: (Int, String, Int))  {
        let (times, suffix, chunkSize) = paras
        let storage = SendableDictionary<Int, ByteBuffer>()
        let tracker = OrderedIndexTracker(maxIndex: times - 1)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await ws.connect(to: "ws://localhost:6500/websocket-echo-\(suffix)") { ws in
                    Task {
                        var printIndex = 0
                        for i in 0..<times {
                            var data = randomData(size: chunkSize)
                            var d = ByteBuffer(integer: i)
                            d.writeBuffer(&data)
                            try await ws.send(d.readBytes(length: chunkSize)!)
                            d.moveReaderIndex(to: 0)
                            storage[i] = d.readSlice(length: 10)
                            if i == (times / 10) * printIndex {
                                printIndex += 1
                                print("writing: \(i)")
                            }
                        }
                        print("writing end: \(times - 1)")
                    }
                    
                    let readCounter = Counter(max: times)
                    
                    ws.onBinary { ws, data in
                        var d = data
                        let index: Int = d.readInteger()!
                        d.moveReaderIndex(to: 0)
                        await tracker.insert(index)
                        #expect(storage[index] != nil)
                        let origin = storage[index]!
                        if origin != d.readSlice(length: 10) {
                            ws.close(promise: nil)
                            #expect(Bool(false));
                        }
                        storage[index] = nil
                        if await index == (times / 10) * readCounter.value {
                            let _ = await readCounter.next()
                            print("reading: \(index)")
                        }
                        
                        if await tracker.isReady() {
                            print("reading end: \(times - 1)")
                            ws.close(promise: nil)
                            semaphore.signal()
                        }
                    }
                    
                    ws.onClose.whenComplete { res in
                        print("Closed")
                        switch res {
                        case .success():
                            semaphore.signal()
                        case .failure(let err):
                            print(err)
                            semaphore.signal()
                        }
                    }
                }
            } catch {
                print(error)
                #expect(Bool(false))
                semaphore.signal()
            }
        }
        semaphore.wait()
        #expect(storage.count == 0)
    }
    
    @Test("连线失败")
    func connectionErrorTest() async throws {
        await #expect(throws: NIOConnectionError.self, performing: { try await ws.connect(to: "ws://127.0.0.1:100000", onUpgrade: { _ in }) })
    }
    
    func randomData(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        var randomBytes = [UInt8](repeating: 0, count: size)
        _ = SecRandomCopyBytes(kSecRandomDefault, size, &randomBytes)
        buffer.writeBytes(randomBytes)
        return buffer
    }
}

