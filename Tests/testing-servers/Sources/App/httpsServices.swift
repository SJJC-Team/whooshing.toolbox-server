import Vapor
import WhooshingServer
import Cryptos

struct HttpsService {
    static func runService() async throws {
        let testPara = Https.Debuging(
            config: .init(name: "Testing-Https-\(Shared.httpsListenPort)", port: Shared.httpsListenPort),
        )
        try await ServiceBootstrap.runHttpsService(with: testPara, routes: routes)
    }
        
    static func routes(_ woo: Whooshing<WhooshingServer.Https>, app: Application) throws {

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
                })
                return response 
            }
        }

        for method in [HTTPMethod.POST, .PATCH, .PUT] {
            app.on(method, "file-echo", body: .stream) { req in
                guard 
                    let fileName = req.headers.first(name: .contentDisposition)
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
                })
                response.headers.replaceOrAdd(name: .contentDisposition, value: fileName)
                return response 
            }
        }

        for (suffix, size) in [
            ("normal", 16384),
            ("largest", Int(UInt32.max))
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
