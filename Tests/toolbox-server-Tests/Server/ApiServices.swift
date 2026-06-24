import Vapor
import WhooshingServer
import Cryptos

struct TestingAuthData: Content, Authenticatable {
    let key: SendableSymmKey
    let token: Token
    
    struct Token: Content {
        let id: UUID
        let userId: UUID
        let credential: String
        let token: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case credential
            case token
        }
    }
}

struct AuthGuardMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let data = try JSONDecoder().decode(TestingAuthData.self, from: request.apiAuthData)
        request.auth.login(data)
        return try await next.respond(to: request)
    }
}

struct ApiService {
    static func bootstrap() async throws -> Whooshing<Api>.BootstrapParas {
        let testPara = Api.Debuging(
            config: .init(
                id: ServiceBootstrap.moduleId,
                name: "testing-module",
                port: TestingShared.apiListenPort
            ),
            authenticationTarget: .url(.init(string: "http://example.com")!)
        ) { authData in
            guard authData.credential.base64EncodedString() == TestingShared.apiClientCredential else { throw Abort(.badRequest, reason: "用户凭据无效") }
            return try Api.Debuging.testingTokenAuth(with: TestingShared.apiClientTokenStr, encrypted: authData.tokenEncrypted)
        }
        
        var logger = Logger(label: "server.api")
        logger.logLevel = TestingShared.logLevel
        return try await Whooshing<Api>.bootstrap(.independentDebug(testPara), logger: logger).get()
    }
    
    static func makeService(paras: Whooshing<Api>.BootstrapParas, inline: Whooshing<Inline>) async throws -> Whooshing<Api> {
        let woo = try await Whooshing<Api>.make(paras, with: inline, with: nil, authGuard: AuthGuardMiddleware()).get()
        try routes(woo, app: woo.app)
        return woo
    }
        
    static func routes(_ woo: Whooshing<WhooshingServer.Api>, app: Application) throws {
        struct Query: Content {
            let value: String
        }

        app.get("string-echo") { req in
            let authData = try req.auth.require(TestingAuthData.self)
            
            guard
                authData.token.id == Api.Debuging.tokenId,
                authData.token.userId == Api.Debuging.userId,
                authData.token.credential == Api.Debuging.credential,
                authData.token.token == Api.Debuging.token
            else {
                throw Abort(.internalServerError, reason: "认证参数未正确加载")
            }
            
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
