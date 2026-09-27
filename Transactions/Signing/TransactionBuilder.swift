import CryptoKit
public import Foundation

/// A stateless assembler for V1 messages with one writable signer and fee payer.
public struct TransactionBuilder: TransactionBuilding {
    /// Creates an assembler without wallet, storage, or networking dependencies.
    public init() {}

    /// Verifies the message's sole signer before appending the V1 signature field.
    ///
    /// The signer comes from the message's first account, not a separate caller value.
    /// This operation checks the header, size, and signature; it doesn't parse
    /// instruction payloads, authorize a transfer, or establish network validity.
    ///
    /// - Parameters:
    ///   - message: The unsigned bytes returned by ``MessageBuilding``.
    ///   - signature: The Ed25519 signature over the entire message.
    /// - Returns: The message followed by its signature, with no padding or length prefix.
    /// - Throws: ``ValidationError/invalidMessage`` for an unsupported header or size,
    ///   or ``ValidationError/invalidSignature`` for a missing or invalid signature.
    public func transaction(for message: Data, signature: Data) throws -> Data {
        // V1's fixed header ends at byte 42; the account array starts with the signer.
        let header = Array(message.prefix(42))
        guard header.count == 42, header[0] == 0x81,
              header[1] == 1, header[2] == 0,
              (1...64).contains(header[41]), header[3] < header[41],
              message.count >= 42 + Int(header[41]) * 32,
              message.count <= 4_096 - 64 else {
            throw ValidationError.invalidMessage
        }
        let publicKey = message.dropFirst(42).prefix(32)
        guard signature.count == 64,
              !PointEncoding.isSmallOrder(publicKey),
              !PointEncoding.isSmallOrder(signature.prefix(32)) else {
            throw ValidationError.invalidSignature
        }
        let signer = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard signer.isValidSignature(signature, for: message) else {
            throw ValidationError.invalidSignature
        }
        var transaction = Data(message)
        transaction.append(signature)
        return transaction
    }
}
