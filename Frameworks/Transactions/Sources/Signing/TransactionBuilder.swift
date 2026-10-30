import CryptoKit
public import Foundation

/// A transaction builder that fills V1 signature slots with verified signatures.
public struct TransactionBuilder: TransactionBuilding {
    private let decoder: any TransactionDecoding = TransactionDecoder()

    /// Creates a transaction builder.
    public init() {}

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

    public func validateSignatures(in transaction: Data) throws -> Transaction {
        let decoded = try decoder.decode(transaction)
        for (index, signature) in decoded.signatures.enumerated() where signature.contains(where: { $0 != 0 }) {
            try verify(signature, publicKey: Data(decoded.accounts[index].address.bytes), message: decoded.message)
        }
        return decoded
    }

    public func validateSignatures(in transaction: Data, for signer: Address) throws -> Transaction {
        let decoded = try validateSignatures(in: transaction)
        try unsignedIndex(for: signer, in: decoded)
        return decoded
    }

    public func transaction(byAdding signature: Data, for signer: Address, to transaction: Data) throws -> Transaction {
        let decoded = try validateSignatures(in: transaction)
        let index = try unsignedIndex(for: signer, in: decoded)
        try verify(signature, publicKey: Data(signer.bytes), message: decoded.message)
        var signatures = decoded.signatures
        signatures[index] = signature
        return Transaction(message: decoded.message, lifetimeSpecifier: decoded.lifetimeSpecifier,
                           accounts: decoded.accounts, requests: decoded.requests,
                           instructions: decoded.instructions, signatures: signatures)
    }

    /// Returns the index of a required signer's empty signature slot.
    ///
    /// - Parameters:
    ///   - signer: The required signer.
    ///   - transaction: The decoded transaction.
    /// - Returns: The signer's signature index.
    /// - Throws: ``ValidationError/signerNotRequired`` or ``ValidationError/signatureAlreadyPresent``.
    @discardableResult
    private func unsignedIndex(for signer: Address, in transaction: Transaction) throws -> Int {
        guard let index = transaction.accounts.firstIndex(where: { $0.address == signer && $0.isSigner }) else {
            throw ValidationError.signerNotRequired
        }
        guard transaction.signatures[index].allSatisfy({ $0 == 0 }) else {
            throw ValidationError.signatureAlreadyPresent
        }
        return index
    }

    /// Verifies an Ed25519 signature of a message.
    ///
    /// - Parameters:
    ///   - signature: The signature.
    ///   - publicKey: The signer's public key.
    ///   - message: The signed bytes.
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
