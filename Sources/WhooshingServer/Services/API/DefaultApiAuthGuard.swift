import Vapor

public struct DefaultApiAuthGuard: AsyncMiddleware {
    public init() {}
    
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let data = request.apiAuthData.data
        request.auth.login(data)
        return try await next.respond(to: request)
    }
}

extension Data: @retroactive Authenticatable {}
