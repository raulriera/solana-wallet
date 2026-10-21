import CryptoKit
import Encoding
import Foundation
import RPC
import Testing
@testable import widgets

/// Verifies a redeem code's text against an independent encoding, its rejections, its equality, and its redaction.
struct RedeemCodeTests {
    /// The secret of every fixture code: the bytes 1 through 32.
    private static let secret = SymmetricKey(data: Data(1...32))

    /// A code's text matches the independent encoding of its network and secret, and reads back as the same code.
    ///
    /// The texts come from a Python reference with its own Base58 and `hashlib`'s SHA-256.
    /// - Parameters:
    ///   - network: The code's network.
    ///   - text: The reference text.
    @Test(arguments: [
        (Network.mainnet, "9ae1uY3ChjejaQoGooB5DA762XQ2yncAKLYEjqqNrPxXMWiAngz"),
        (.devnet, "9cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jF"),
    ])
    func `Codes encode as the reference does and read back`(network: Network, text: String) throws {
        let code = try RedeemCode(secret: Self.secret, network: network)

        #expect(code.text == text)
        #expect(try RedeemCode(text: text) == code)
    }

    /// Text that isn't a whole, current code for a known network is rejected.
    /// - Parameter text: The rejected text.
    @Test(arguments: [
        "",
        "9cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jF ",
        "9cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2j",
        "9cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jG",
        "0cam5mVEZAKxiENyiNo5AUhrwe1kdVT36ycLyzXGr3xur4KS2jF",
    ])
    func `Damaged text is rejected`(text: String) {
        #expect(throws: PrivateBalanceError.invalidCode) { try RedeemCode(text: text) }
    }

    /// Bytes with another version, an unknown network, a changed checksum, or another length are rejected.
    /// - Parameter bytes: The encoded bytes.
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

    /// Only a 32-byte secret makes a code.
    @Test
    func `Secrets of another length are rejected`() {
        #expect(throws: PrivateBalanceError.invalidCode) {
            try RedeemCode(secret: SymmetricKey(data: Data(1...31)), network: .devnet)
        }
    }

    /// Codes are equal only with the same secret and network.
    @Test
    func `Codes compare their secret and network`() throws {
        let code = try RedeemCode(secret: Self.secret, network: .devnet)

        #expect(code != (try RedeemCode(secret: Self.secret, network: .mainnet)))
        #expect(code != (try RedeemCode(secret: SymmetricKey(data: Data(2...33)), network: .devnet)))
    }

    /// Printing, dumping, and reflecting a code omit its secret.
    @Test
    func `Descriptions omit the secret`() throws {
        let code = try RedeemCode(secret: Self.secret, network: .devnet)
        var dumped = ""
        dump(code, to: &dumped)

        #expect(String(describing: code) == "RedeemCode")
        #expect(String(reflecting: code) == "RedeemCode")
        #expect(dumped == "- RedeemCode\n")
    }

    /// Encodes a code's bytes with chosen fields.
    /// - Parameters:
    ///   - version: The version byte.
    ///   - network: The network byte.
    ///   - checksumOffset: A value added to the checksum's first byte, or zero for the valid checksum.
    /// - Returns: The version, network, fixture secret, and checksum bytes.
    private static func encoded(version: UInt8, network: UInt8, checksumOffset: UInt8 = 0) -> [UInt8] {
        let payload = [version, network] + Array(1...32)
        var checksum = Array(SHA256.hash(data: payload).prefix(4))
        checksum[0] &+= checksumOffset
        return payload + checksum
    }
}
