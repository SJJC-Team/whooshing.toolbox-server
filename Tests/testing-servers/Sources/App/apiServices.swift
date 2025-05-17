import Vapor
import WhooshingServer
import Cryptos

struct ApiService {
    static func runService(inline: Whooshing<Inline>) async throws {
        let testPara = API.Debuging(config: .init(name: "Tesing-API-6502", port: 6502)) { authData in
            guard authData.credential.base64EncodedString() == Shared.apiClientCredential else { throw Abort(.badRequest, reason: "用户凭据无效") }
            return try API.Debuging.testingTokenAuth(with: Shared.apiClientTokenStr, encrypted: authData.tokenEncrypted)
        }
        try await ServiceBootstrap.runApiService(with: testPara, inline: inline, routes: routes)
    }
        
    static func routes(_ woo: Whooshing<WhooshingServer.API>, app: Application) throws {
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
