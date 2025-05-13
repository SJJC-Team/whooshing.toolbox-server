import WhooshingClient
import Vapor

extension WebURI {
    var uri: URI {
        .init(stringLiteral: self.string)
    }
}
