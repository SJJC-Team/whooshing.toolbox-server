import Vapor
import DataConvertable
import Cryptos
import NIO
import WhooshingClient

extension Data: @retroactive AsyncResponseEncodable {}
extension Data: @retroactive AsyncRequestDecodable {}
extension Data: @retroactive ResponseEncodable {}
extension Data: @retroactive RequestDecodable {}
extension Data: @retroactive Content {}


extension Crypto.Symm.Key: @retroactive AsyncResponseEncodable {}
extension Crypto.Symm.Key: @retroactive AsyncRequestDecodable {}
extension Crypto.Symm.Key: @retroactive ResponseEncodable {}
extension Crypto.Symm.Key: @retroactive RequestDecodable {}
extension Crypto.Symm.Key: @retroactive Content {}


extension Crypto.Asym.CPrivateKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.CPrivateKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.CPrivateKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.CPrivateKey: @retroactive RequestDecodable {}
extension Crypto.Asym.CPrivateKey: @retroactive Content {}


extension Crypto.Asym.CPublicKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.CPublicKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.CPublicKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.CPublicKey: @retroactive RequestDecodable {}
extension Crypto.Asym.CPublicKey: @retroactive Content {}


extension Crypto.Asym.SPrivateKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.SPrivateKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.SPrivateKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.SPrivateKey: @retroactive RequestDecodable {}
extension Crypto.Asym.SPrivateKey: @retroactive Content {}


extension Crypto.Asym.SPublicKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.SPublicKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.SPublicKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.SPublicKey: @retroactive RequestDecodable {}
extension Crypto.Asym.SPublicKey: @retroactive Content {}

