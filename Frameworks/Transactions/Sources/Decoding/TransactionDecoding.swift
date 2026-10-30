public import Foundation

/// A type that decodes serialized V1 transactions.
public protocol TransactionDecoding: Sendable {
    /// Decodes a Base64-encoded V1 transaction.
    ///
    /// - Parameter base64: The Base64-encoded V1 envelope.
    /// - Returns: The decoded transaction.
    /// - Throws: ``ValidationError`` for malformed Base64 or an invalid V1 envelope.
    func decode(base64: String) throws -> Transaction

    /// Decodes a V1 transaction.
    ///
    /// - Parameter data: A complete V1 envelope, including every signature slot.
    /// - Returns: The message bytes, ordered accounts, requests, instructions, and signatures.
    /// - Throws: ``ValidationError`` for unsupported or malformed input.
    func decode(_ data: Data) throws -> Transaction
}
