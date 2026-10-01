public import Foundation

/// A type that inspects complete serialized V1 transactions without signing them.
public protocol TransactionDecoding: Sendable {
    /// Imports a Base64 transaction into the typed representation used by app services.
    ///
    /// - Parameter base64: The complete encoded V1 envelope received at an import boundary.
    /// - Returns: Structural inspection with the original message and signature slots preserved.
    /// - Throws: ``ValidationError`` for malformed Base64 or an invalid V1 envelope.
    func decode(base64: String) throws -> Transaction

    /// Decodes a bounded V1 transaction while preserving the exact signed message.
    ///
    /// Signature slots may be empty or contain unverified signatures. Successful
    /// decoding doesn't establish program intent, signature validity, or user consent.
    ///
    /// - Parameter data: A complete V1 envelope, including every signature slot.
    /// - Returns: The message bytes, ordered accounts, requests, instructions, and signatures.
    /// - Throws: ``ValidationError`` for unsupported or malformed input.
    func decode(_ data: Data) throws -> Transaction
}
