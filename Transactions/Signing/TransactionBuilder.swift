import CryptoKit
public import Foundation

/// A stateless assembler that preserves V1 messages and verifies supplied signatures.
public struct TransactionBuilder: TransactionBuilding {
    private let decoder: any TransactionDecoding

    /// Creates an assembler with a structural decoder and no wallet or network access.
    ///
    /// - Parameter decoder: The decoder used to inspect complete transaction envelopes.
    public init(decoder: any TransactionDecoding = TransactionDecoder()) {
        self.decoder = decoder
    }

    /// Appends a placeholder signature to a single-signer V1 message.
    ///
    /// These bytes only support simulation with signature verification disabled.
    /// They do not authorize a transfer and cannot be submitted as a signed transaction.
    ///
    /// - Parameter message: The unsigned bytes returned by ``MessageBuilding``.
    /// - Returns: The unchanged message followed by one empty 64-byte signature slot.
    /// - Throws: ``ValidationError/invalidMessage`` for an unsupported header or size.
    public func simulationTransaction(for message: Data) throws -> Data {
        try validateMessage(message)
        return message + Data(repeating: 0, count: 64)
    }

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
        try validateMessage(message)
        let publicKey = message.dropFirst(42).prefix(32)
        try verify(signature, publicKey: publicKey, message: message)
        return message + signature
    }

    /// Decodes an envelope and verifies every occupied signature slot.
    ///
    /// - Parameter transaction: Complete V1 bytes, including any empty signature slots.
    /// - Returns: The inspected transaction; empty slots remain unsigned.
    /// - Throws: A structural or signature validation error.
    public func validateSignatures(in transaction: Data) throws -> Transaction {
        let decoded = try decoder.decode(transaction)
        for (index, signature) in decoded.signatures.enumerated() where signature.contains(where: { $0 != 0 }) {
            try verify(signature, publicKey: Data(decoded.accounts[index].address.bytes), message: decoded.message)
        }
        return decoded
    }

    /// Verifies existing signatures and the selected signer's empty slot.
    ///
    /// - Parameters:
    ///   - transaction: A complete V1 envelope, potentially with empty slots.
    ///   - signer: The required signer whose slot must still be empty.
    /// - Returns: The decoded transaction; zero-filled slots remain unsigned.
    /// - Throws: A validation error for malformed data, invalid signatures, an unrelated
    ///   account, or an occupied selected slot.
    public func validateSignatures(in transaction: Data, for signer: Address) throws -> Transaction {
        let decoded = try validateSignatures(in: transaction)
        _ = try unsignedIndex(for: signer, in: decoded)
        return decoded
    }

    /// Fills the selected required signer's empty slot, retaining all other envelope bytes.
    ///
    /// - Parameters:
    ///   - signature: The signature to verify against the selected account and message.
    ///   - signer: The required signer whose empty slot to fill.
    ///   - transaction: The original complete envelope.
    /// - Returns: A typed transaction that may still lack other required signatures.
    /// - Throws: ``ValidationError`` if the envelope, account, or signatures are invalid.
    public func transaction(byAdding signature: Data, for signer: Address, to transaction: Data) throws -> Transaction {
        let decoded = try validateSignatures(in: transaction, for: signer)
        let index = try unsignedIndex(for: signer, in: decoded)
        try verify(signature, publicKey: Data(signer.bytes), message: decoded.message)
        var signatures = decoded.signatures
        signatures[index] = signature
        return Transaction(message: decoded.message, lifetimeSpecifier: decoded.lifetimeSpecifier,
                           accounts: decoded.accounts, requests: decoded.requests,
                           instructions: decoded.instructions, signatures: signatures)
    }

    /// Locates an empty required-signature slot in structurally validated data.
    ///
    /// - Parameters:
    ///   - signer: The selected account whose signature is requested.
    ///   - transaction: The decoded envelope.
    /// - Returns: The selected account's signature index.
    /// - Throws: A validation error for an unrelated account or occupied slot.
    private func unsignedIndex(for signer: Address, in transaction: Transaction) throws -> Int {
        guard let index = transaction.accounts.firstIndex(where: { $0.address == signer && $0.isSigner }) else {
            throw ValidationError.signerNotRequired
        }
        guard transaction.signatures[index].allSatisfy({ $0 == 0 }) else {
            throw ValidationError.signatureAlreadyPresent
        }
        return index
    }

    /// Applies the same strict point and signature checks to every assembly path.
    ///
    /// - Parameters:
    ///   - signature: The Ed25519 signature to validate.
    ///   - publicKey: The encoded required signer's public key.
    ///   - message: The exact bytes that must have been signed.
    /// - Throws: ``ValidationError/invalidSignature`` if any check fails.
    private func verify(_ signature: Data, publicKey: Data, message: Data) throws {
        guard signature.count == 64,
              !PointEncoding.isSmallOrder(publicKey),
              !PointEncoding.isSmallOrder(signature.prefix(32)) else {
            throw ValidationError.invalidSignature
        }
        let signer = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard signer.isValidSignature(signature, for: message) else {
            throw ValidationError.invalidSignature
        }
    }

    /// Checks the header and size shared by simulated and signed envelopes.
    ///
    /// - Parameter message: The bytes whose single-signer V1 layout to check.
    /// - Throws: ``ValidationError/invalidMessage`` for an unsupported header or size.
    private func validateMessage(_ message: Data) throws {
        // V1's fixed header ends at byte 42; the account array starts with the signer.
        let header = Array(message.prefix(42))
        guard header.count == 42, header[0] == 0x81,
              header[1] == 1, header[2] == 0,
              (1...64).contains(header[41]), header[3] < header[41],
              message.count >= 42 + Int(header[41]) * 32,
              message.count <= 4_096 - 64 else {
            throw ValidationError.invalidMessage
        }
    }
}
