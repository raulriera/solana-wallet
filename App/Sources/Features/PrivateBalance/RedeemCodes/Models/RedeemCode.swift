import CryptoKit
import Encoding
import Foundation
import RPC
import Redaction

/// A redeem code: the secret of a one-time account that holds private and public SOL, and its network.
nonisolated struct RedeemCode: Sendable, Equatable, Redacted {
    private static let version: UInt8 = 1

    /// The length of a secret, in bytes.
    private static let secretLength = 32

    /// The length of a checksum, in bytes.
    private static let checksumLength = 4

    /// The length of a code, in bytes.
    private static let length = 2 + secretLength + checksumLength

    /// The secret of the code's one-time account.
    let secret: SymmetricKey

    let network: Network

    /// The code's Base58 text.
    var text: String {
        let payload = [Self.version, network.redeemCodeByte] + secret.withUnsafeBytes { Array($0) }
        return Base58.encode(payload + Self.checksum(of: payload))
    }

    /// Creates a code from a one-time account's secret and network.
    ///
    /// - Parameters:
    ///   - secret: The one-time account's 32-byte secret.
    ///   - network: The network that holds the code's SOL.
    /// - Throws: ``PrivateBalanceError/invalidCode`` for a secret that isn't 32 bytes.
    init(secret: SymmetricKey, network: Network) throws {
        guard secret.bitCount == Self.secretLength * 8 else { throw PrivateBalanceError.invalidCode }
        self.secret = secret
        self.network = network
    }

    /// Creates a code from its text.
    ///
    /// - Parameter text: The code's Base58 text.
    /// - Throws: ``PrivateBalanceError/invalidCode`` for text that isn't a valid code.
    init(text: String) throws {
        guard var bytes = Base58.decode(text, byteCount: Self.length) else { throw PrivateBalanceError.invalidCode }
        var payload = Array(bytes.dropLast(Self.checksumLength))
        defer {
            bytes.indices.forEach { bytes[$0] = 0 }
            payload.indices.forEach { payload[$0] = 0 }
        }
        guard bytes[0] == Self.version, let network = Network(redeemCodeByte: bytes[1]),
              Array(bytes.suffix(Self.checksumLength)) == Self.checksum(of: payload) else {
            throw PrivateBalanceError.invalidCode
        }
        try self.init(secret: SymmetricKey(data: payload.dropFirst(2)), network: network)
    }

    static func == (lhs: RedeemCode, rhs: RedeemCode) -> Bool {
        lhs.network == rhs.network
            && lhs.secret.withUnsafeBytes { left in rhs.secret.withUnsafeBytes { right in left.elementsEqual(right) } }
    }

    /// Returns a code's checksum.
    ///
    /// - Parameter payload: The version, network, and secret bytes.
    /// - Returns: The first 4 bytes of the payload's SHA-256 digest.
    private static func checksum(of payload: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: payload).prefix(checksumLength))
    }
}

nonisolated private extension Network {
    /// The byte that names the network in a redeem code.
    var redeemCodeByte: UInt8 {
        switch self {
        case .mainnet: 0
        case .devnet: 1
        }
    }

    /// Creates the network that a redeem code's byte names.
    ///
    /// - Parameter redeemCodeByte: The code's network byte.
    init?(redeemCodeByte: UInt8) {
        switch redeemCodeByte {
        case 0: self = .mainnet
        case 1: self = .devnet
        default: return nil
        }
    }
}
