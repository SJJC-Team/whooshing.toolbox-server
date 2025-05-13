import WhooshingClient
import Vapor

extension HTTPRequest: @retroactive AsyncResponseEncodable {}
extension HTTPRequest: @retroactive AsyncRequestDecodable {}
extension HTTPRequest: @retroactive ResponseEncodable {}
extension HTTPRequest: @retroactive RequestDecodable {}
extension HTTPRequest: @retroactive Content {}

extension HTTPResponse: @retroactive AsyncResponseEncodable {}
extension HTTPResponse: @retroactive AsyncRequestDecodable {}
extension HTTPResponse: @retroactive ResponseEncodable {}
extension HTTPResponse: @retroactive RequestDecodable {}
extension HTTPResponse: @retroactive Content {}
