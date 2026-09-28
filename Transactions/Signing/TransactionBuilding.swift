public import Foundation

/// A type that validates and assembles V1 signature slots without changing messages.
public protocol TransactionBuilding: Sendable {
    /// Appends an empty slot for every required signer without signing.
    ///
    /// - Parameter message: Unsigned V1 bytes produced by ``MessageBuilding``.
    /// - Returns: Transaction bytes for simulation with signature verification disabled.
    /// - Throws: A structural validation error for an unsupported header, size, or message.
    func simulationTransaction(for message: Data) throws -> Data

    /// Decodes an envelope and verifies each occupied signature slot.
    ///
    /// - Parameter transaction: Complete V1 bytes, including any empty signature slots.
    /// - Returns: The inspected transaction; empty slots remain unsigned.
    /// - Throws: A structural or signature validation error.
    func validateSignatures(in transaction: Data) throws -> Transaction

    /// Decodes an envelope and verifies every signature that is already present.
    ///
    /// - Parameters:
    ///   - transaction: Complete V1 bytes, including zero-filled missing slots.
    ///   - signer: The selected required signer whose slot must still be empty.
    /// - Returns: The structural contents with every nonzero signature verified.
    /// - Throws: A validation error for malformed data, invalid signatures, an unrelated
    ///   account, or an occupied selected slot.
    func validateSignatures(in transaction: Data, for signer: Address) throws -> Transaction

    /// Adds a verified signature to its account's empty slot without modifying other bytes.
    ///
    /// - Parameters:
    ///   - signature: The signature covering the exact encoded message.
    ///   - signer: The account whose required signature slot to fill.
    ///   - transaction: The complete unsigned or partially signed V1 envelope.
    /// - Returns: A typed transaction with only the selected empty signature slot filled.
    /// - Throws: A validation error for malformed data, invalid signatures, an unrelated
    ///   account, or an occupied signature slot.
    func transaction(byAdding signature: Data, for signer: Address, to transaction: Data) throws -> Transaction
}
