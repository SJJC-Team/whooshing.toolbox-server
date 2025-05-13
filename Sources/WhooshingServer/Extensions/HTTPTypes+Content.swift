import WhooshingClient
import Vapor

extension HTTPResponse: @retroactive AsyncResponseEncodable {
    public func encodeResponse(for request: Request) async throws -> Response {
        let body: Response.Body
        if let buffer = self.body {
            body = .init(buffer: buffer)
        } else {
            body = .empty
        }
        let response = Response(
            status: self.status,
            version: self.version,
            headers: self.headers,
            body: body
        )
        return response
    }
}

extension HTTPResponse: @retroactive ResponseEncodable {
    public func encodeResponse(for request: Request) -> EventLoopFuture<Response> {
        let body: Response.Body
        if let buffer = self.body {
            body = .init(buffer: buffer, byteBufferAllocator: request.byteBufferAllocator)
        } else {
            body = .empty
        }
        let response = Response(
            status: self.status,
            version: self.version,
            headers: self.headers,
            body: body
        )
        return request.eventLoop.makeSucceededFuture(response)
    }
}
extension HTTPResponse: @retroactive Content {}
