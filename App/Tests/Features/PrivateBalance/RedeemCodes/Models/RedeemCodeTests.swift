import CryptoKit
import Encoding
import Foundation
import RPC
import Testing
@testable import widgets

struct RedeemCodeTests {
    private static let secret = SymmetricKey(data: Data(1...32))

    @Test(arguments: [
        (Network.mainnet, "9ae1uY3ChjejaQoGooB5DA762XQ2yncAKLYEjqqNrPxXMWiAngz"),
        (.devnet, "9cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jF"),
    ])
    func `Codes encode as the reference does and read back`(network: Network, text: String) throws {
        let code = try RedeemCode(secret: Self.secret, network: network)

        #expect(code.text == text)
        #expect(try RedeemCode(text: text) == code)
    }

    @Test(arguments: [
        "",
        "9cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jF ",
        "0cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jF",
    ])
    func `Damaged text is rejected`(text: String) {
        #expect(throws: PrivateBalanceError.invalidCode) { try RedeemCode(text: text) }
    }

    @Test(arguments: [
        RedeemCodeTests.encoded(version: 2, network: 1),
        RedeemCodeTests.encoded(version: 1, network: 2),
        RedeemCodeTests.encoded(version: 1, network: 1, checksumOffset: 1),
        Array(RedeemCodeTests.encoded(version: 1, network: 1).dropLast()),
        RedeemCodeTests.encoded(version: 1, network: 1) + [0],
    ])
    func `Codes with invalid fields are rejected`(bytes: [UInt8]) {
        #expect(throws: PrivateBalanceError.invalidCode) { try RedeemCode(text: Base58.encode(bytes)) }
    }

    @Test
    func `Secrets of another length are rejected`() {
        #expect(throws: PrivateBalanceError.invalidCode) {
            try RedeemCode(secret: SymmetricKey(data: Data(1...31)), network: .devnet)
        }
    }

    @Test
    func `Codes compare their secret and network`() throws {
        let code = try RedeemCode(secret: Self.secret, network: .devnet)

        #expect(code != (try RedeemCode(secret: Self.secret, network: .mainnet)))
        #expect(code != (try RedeemCode(secret: SymmetricKey(data: Data(2...33)), network: .devnet)))
    }

    private static func encoded(version: UInt8, network: UInt8, checksumOffset: UInt8 = 0) -> [UInt8] {
        let payload = [version, network] + Array(1...32)
        var checksum = Array(SHA256.hash(data: payload).prefix(4))
        checksum[0] &+= checksumOffset
        return payload + checksum
    }
}
