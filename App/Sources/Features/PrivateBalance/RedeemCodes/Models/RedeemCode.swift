import CryptoKit
import Encoding
import Foundation
import RPC

/// A redeem code: the secret of a one-time account that holds private and public SOL, and the network that holds it.
///
/// Like cash, anyone with the code can redeem it. Its text, which a QR code and the share sheet carry unchanged, is the
/// Base58 encoding of 38 bytes: the version 1, the network's byte, the 32-byte secret, and the first 4 bytes of the
/// SHA-256 digest of the previous 34 bytes. Descriptions and reflection omit the secret.
nonisolated struct RedeemCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// The version byte that starts every code's bytes.
    private static let version: UInt8 = 1

    /// The length of a secret.
    private static let secretLength = 32

    /// The length of the checksum that ends a code's bytes.
    private static let checksumLength = 4

    /// The length of a code's bytes: the version, the network, the secret, and the checksum.
    private static let length = 2 + secretLength + checksumLength

    /// The 32-byte secret of the code's one-time account.
    let secret: SymmetricKey

    /// The network whose one-time account holds the code's SOL.
    let network: Network

    /// The code's Base58 text.
    var text: String {
        let payload = [Self.version, network.redeemCodeByte] + secret.withUnsafeBytes { Array($0) }
        return Base58.encode(payload + Self.checksum(of: payload))
    }

    /// A description that omits the secret.
    var description: String { "RedeemCode" }

    /// A debugging description that omits the secret.
    var debugDescription: String { description }

    /// A reflection view that omits the secret.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Pairs a one-time account's secret with its network.
    /// - Parameters:
    ///   - secret: The one-time account's 32-byte secret.
    ///   - network: The network that holds the code's SOL.
    /// - Throws: ``PrivateBalanceError/invalidCode`` for a secret that isn't 32 bytes.
    init(secret: SymmetricKey, network: Network) throws {
        guard secret.bitCount == Self.secretLength * 8 else { throw PrivateBalanceError.invalidCode }
        self.secret = secret
        self.network = network
    }

    /// Reads a code from its text.
    ///
    /// The text must be exact: whitespace and other characters outside the Base58 alphabet are rejected. The decoded
    /// bytes are erased on a best-effort basis.
    /// - Parameter text: The code's Base58 text.
    /// - Throws: ``PrivateBalanceError/invalidCode`` for text that isn't Base58 of 38 bytes, or that has another
    ///   version, an unknown network byte, or a checksum that doesn't match.
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

    /// Compares two codes by their secret and network.
    /// - Parameters:
    ///   - lhs: A code.
    ///   - rhs: Another code.
    /// - Returns: Whether both codes hold the same one-time account on the same network.
    static func == (lhs: RedeemCode, rhs: RedeemCode) -> Bool {
        lhs.network == rhs.network
            && lhs.secret.withUnsafeBytes { left in rhs.secret.withUnsafeBytes { right in left.elementsEqual(right) } }
    }

    /// Computes a code's checksum.
    /// - Parameter payload: The version, network, and secret bytes.
    /// - Returns: The first 4 bytes of the payload's SHA-256 digest.
    private static func checksum(of payload: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: payload).prefix(checksumLength))
    }
}

nonisolated private extension Network {
    /// The byte that names the network in a redeem code: 0 for mainnet and 1 for devnet.
    var redeemCodeByte: UInt8 {
        switch self {
        case .mainnet: 0
        case .devnet: 1
        }
    }

    /// Reads the network that a redeem code's byte names.
    /// - Parameter redeemCodeByte: The code's network byte.
    init?(redeemCodeByte: UInt8) {
        switch redeemCodeByte {
        case 0: self = .mainnet
        case 1: self = .devnet
        default: return nil
        }
    }
}
