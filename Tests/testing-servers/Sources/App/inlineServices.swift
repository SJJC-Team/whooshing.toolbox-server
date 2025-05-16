import Vapor
import WhooshingServer
import Cryptos

struct InlineService1 {
    
    static func makeService() async throws -> Whooshing<Inline> {
        let testPara = Inline.Debuging(
            rootKey: Shared.rootKey,
            config: .init(name: "Testing-Inline-6500", port: 6500),
            serviceId: Shared.serviceIds[0],
            moduleDatas: Shared.serviceIds.enumerated().map {
                .init(name: "Testing-Inline-\(6500 + $0)", serviceId: $1, connection: nil)
            }
        )
        let woo = try await Whooshing<Inline>.make(.independentDebug(testPara))
        try routes(woo, app: woo.app)
        return woo
    }
        
    static func routes(_ woo: Whooshing<WhooshingServer.Inline>, app: Application) throws {

        struct Query: Content {
            let value: String
        }

        app.get("string-echo") { req in
            let str = try req.query.decode(Query.self).value
            return str
        }

        for method in [HTTPMethod.POST, .PATCH, .PUT, .DELETE] {
            app.on(method, "string-echo") { req in
                let str = try req.content.decode(String.self)
                return str
            }
        }

        for method in [HTTPMethod.GET, .POST, .PATCH, .PUT, .DELETE] {
            app.on(method, "no-body") { req in
                return "NO-BODY"
            }
        }

        for method in [HTTPMethod.POST, .PATCH, .PUT] {
            app.on(method, "streaming-echo", body: .stream) { req in
                guard 
                    let contentSizeStr = req.headers.first(name: .contentLength),
                    let contentSize = Int(contentSizeStr) 
                else {
                    throw Abort(.badRequest)
                }
                let response = Response(status: .ok)
                response.body = .init(asyncStream: { writer in
                    do {
                        for try await chunk in req.body {
                            try await writer.write(.buffer(chunk))
                        }
                        try await writer.write(.end)
                    } catch {
                        try await writer.write(.end)
                        throw error
                    }
                }, count: contentSize)
                return response 
            }
        }

        for method in [HTTPMethod.POST, .PATCH, .PUT] {
            app.on(method, "file-echo", body: .stream) { req in
                guard 
                    let fileName = req.headers.first(name: .contentDisposition),
                    let contentSizeStr = req.headers.first(name: .contentLength),
                    let contentSize = Int(contentSizeStr)
                else { 
                    throw Abort(.badRequest) 
                }
                let response = Response(status: .ok)
                response.body = .init(asyncStream: { writer in
                    do {
                        for try await chunk in req.body {
                            try await writer.write(.buffer(chunk))
                        }
                        try await writer.write(.end)
                    } catch {
                        try await writer.write(.end)
                        throw error
                    }
                }, count: contentSize)
                response.headers.replaceOrAdd(name: .contentDisposition, value: fileName)
                return response 
            }
        }

        for (suffix, size) in [
            ("normal", 16384),
            ("largest", ChunkTool.maxChunk)
        ] {
            app.webSocket("websocket-echo-\(suffix)", maxFrameSize: .init(integerLiteral: size)) { req, ws in
                ws.onBinary { ws, data in
                    ws.send(data)
                }
                ws.onClose.whenComplete { result in
                    switch result {
                    case .success:
                        ws.close(promise: nil)
                        print("WebSocket 正常关闭")
                    case .failure(let error):
                        ws.close(promise: nil)
                        print("WebSocket 错误关闭: \(error)")
                    }
                }
            }
        }
    }
}

struct InlineService2 {
    static func runService() async throws {
        let testPara = Inline.Debuging(
            rootKey: Shared.rootKey,
            config: .init(name: "Testing-Inline-6501", port: 6501),
            serviceId: Shared.serviceIds[1],
            moduleDatas: Shared.serviceIds.enumerated().map {
                .init(name: "Testing-Inline-\(6500 + $0)", serviceId: $1, connection: nil)
            }
        )
        
        try await ServiceBootstrap.runInlineService(with: testPara, routes: routes)
    }
        
    static func routes(_ woo: Whooshing<WhooshingServer.Inline>, app: Application) throws {
        app.get("hello") { req in
            return "asfasdfafd"
        }
    }
}
