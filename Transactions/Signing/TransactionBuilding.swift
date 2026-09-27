public import Foundation

/// A type that assembles locally signed, single-signer V1 transactions.
public protocol TransactionBuilding: Sendable {
    /// Verifies a signature and appends it to the original V1 message.
    ///
    /// - Parameters:
    ///   - message: Unsigned V1 bytes produced by ``MessageBuilding``.
    ///   - signature: The 64-byte Ed25519 signature covering those exact bytes.
    /// - Returns: Transaction bytes for simulation or submission through RPC.
    /// - Throws: ``ValidationError/invalidMessage`` for an unsupported header or size,
    ///   or ``ValidationError/invalidSignature`` if signature verification fails.
    func transaction(for message: Data, signature: Data) throws -> Data
}
