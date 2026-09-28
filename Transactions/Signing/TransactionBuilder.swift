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

    /// Appends an empty slot for each required signer and validates the complete envelope.
    ///
    /// - Parameter message: A compiled V1 message, excluding signatures.
    /// - Returns: The unchanged message with ordered placeholder signatures for simulation.
    /// - Throws: A validation error for an unsupported header, malformed message, or oversized envelope.
    public func simulationTransaction(for message: Data) throws -> Data {
        guard message.count >= 2, message.first == 0x81 else { throw ValidationError.invalidMessage }
        let count = Int(message[message.startIndex + 1])
        guard (1...12).contains(count), message.count + count * 64 <= 4_096 else {
            throw ValidationError.invalidMessage
        }
        let envelope = message + Data(repeating: 0, count: count * 64)
        let decoded = try decoder.decode(envelope)
        guard decoded.message == message else { throw ValidationError.invalidMessage }
        return envelope
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
}
