public import Foundation

/// A type that constructs native SOL transfer messages without signing or networking.
public protocol MessageBuilding: Sendable {
    /// Encodes a V1 message for fee estimation and subsequent signing.
    ///
    /// - Parameters:
    ///   - transfer: The validated sender, recipient, and lamport amount.
    ///   - recentBlockhash: The Base58 blockhash obtained from RPC.
    ///   - configuration: The explicit priority fee and resource requests.
    /// - Returns: Message bytes, excluding signatures. Simulation and submission
    ///   require a complete transaction envelope, which this method doesn't create.
    /// - Throws: ``ValidationError/invalidBlockhash`` if the blockhash encoding is invalid.
    func message(
        for transfer: Transfer,
        recentBlockhash: String,
        configuration: Configuration
    ) throws -> Data
}
