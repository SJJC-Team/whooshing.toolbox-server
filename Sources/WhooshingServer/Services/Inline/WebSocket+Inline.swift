import WhooshingClient
import WhooshingWebSocket
import Logging
import Vapor

final class InlineWebSocket: WhooshingWebSocket, StorageKey, Sendable {
    typealias Value = InlineWebSocket
    static let loggerLabel = "Inline.WS.Client"
    let logger: Logger?
    let client: InlineClient
    
    init(client: InlineClient) {
        self.logger = client.logger
        self.client = client
    }
}
