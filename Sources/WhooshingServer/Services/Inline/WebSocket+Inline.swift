import WhooshingClient
import WhooshingWebSocket
import Logging
import Vapor

final class InlineWebSocket: WhooshingWebSocket, StorageKey, Sendable {
    typealias Value = InlineWebSocket
    static let loggerLabel = "Inline.WS.Client"
    let logger: Logger?
    let client: InlineReqClient
    
    init(client: InlineReqClient) {
        self.logger = client.logger
        self.client = client
    }
}
