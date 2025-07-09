import WhooshingClient
import Vapor

extension HTTPResponse: @retroactive AsyncResponseEncodable {
    @inlinable
    public func encodeResponse(for request: Request) async throws -> Response {
        return try await encodeResponse(for: request).get()
    }
}

extension HTTPResponse: @retroactive ResponseEncodable {
    @inlinable
    public func encodeResponse(for request: Request) -> EventLoopFuture<Response> {
        request.eventLoop.makeFutureWithTask {
            let b: Response.Body
            if let body = self.body?.type {
                switch body {
                case .bytes(let bytes): b = .init(buffer: bytes)
                case .stream(let asyncBytes):
                    b = .init(asyncStream: { writer in
                        for try await chunk in asyncBytes {
                            try await writer.write(.buffer(chunk))
                        }
                    })
                }
            } else {
                b = .empty
            }
            return Response(
                status: self.status,
                version: self.version,
                headers: self.headers,
                body: b
            )
        }
    }
}

public extension WebURI {
    @inlinable
    var uri: URI {
        .init(stringLiteral: self.string)
    }
}

public extension ApiClient {
    /// 使用 Vapor `Request` 实例初始化 API 客户端。
    ///
    /// 此构造函数会使用 Vapor 提供的事件循环组、日志器和 ByteBuffer 分配器来配置底层客户端，
    /// 并将用户凭证与令牌存储到请求上下文中，供后续身份验证使用。
    ///
    /// - Parameters:
    ///   - credential: 用户凭据（Base64 编码的字符串）。
    ///   - token: 用户令牌（Base64 编码的字符串）。
    ///   - request: 当前的 Vapor Request 实例。
    @inlinable
    convenience init(credential: String, token: String, request: Request) {
        self.init(credential: credential, token: token, eventLoop: request.eventLoop, logger: request.logger)
    }
}
