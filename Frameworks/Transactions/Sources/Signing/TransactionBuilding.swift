public import Foundation

/// A type that validates and fills V1 transaction signature slots.
public protocol TransactionBuilding: Sendable {
    /// Returns a transaction with an empty signature slot for every required signer.
    ///
    /// - Parameter message: The V1 message bytes.
    /// - Returns: The unsigned transaction bytes.
    /// - Throws: A validation error for an unsupported header, size, or message.
    func simulationTransaction(for message: Data) throws -> Data

    /// Decodes an envelope and verifies each occupied signature slot.
    ///
    /// - Parameter transaction: The V1 transaction bytes.
    /// - Returns: The decoded transaction.
    /// - Throws: A structural or signature validation error.
    func validateSignatures(in transaction: Data) throws -> Transaction

    /// Decodes an envelope and verifies every signature that is already present.
    ///
    /// - Parameters:
    ///   - transaction: The V1 transaction bytes.
    ///   - signer: The required signer whose slot must still be empty.
    /// - Returns: The decoded transaction.
    /// - Throws: A validation error for malformed data, an invalid signature, or an unusable signer slot.
    func validateSignatures(in transaction: Data, for signer: Address) throws -> Transaction

    /// Adds a verified signature to its signer's empty slot.
    ///
    /// - Parameters:
    ///   - signature: The signature of the encoded message.
    ///   - signer: The account whose signature slot to fill.
    ///   - transaction: The unsigned or partially signed V1 transaction bytes.
    /// - Returns: The transaction with the signature added.
    /// - Throws: A validation error for malformed data, an invalid signature, or an unusable signer slot.
    func transaction(byAdding signature: Data, for signer: Address, to transaction: Data) throws -> Transaction
}
