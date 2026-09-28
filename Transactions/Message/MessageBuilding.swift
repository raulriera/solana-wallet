public import Foundation

/// A type that constructs native SOL transfer messages without signing or networking.
public protocol MessageBuilding: Sendable {
    /// Encodes a V1 message for fee estimation and subsequent signing.
    ///
    /// - Parameters:
    ///   - transfers: The transfers in execution order, sharing one sender and fee payer.
    ///   - recentBlockhash: The Base58 blockhash obtained from RPC.
    ///   - configuration: The explicit priority fee and resource requests.
    /// - Returns: Message bytes, excluding signatures. Simulation and submission
    ///   require a complete transaction envelope, which this method doesn't create.
    /// - Throws: A validation error for an empty list, different senders, or invalid encoding.
    func message(
        for transfers: [Transfer],
        recentBlockhash: String,
        configuration: Configuration
    ) throws -> Data
}

extension MessageBuilding {
    /// Encodes one SOL transfer using the shared message construction path.
    ///
    /// - Parameters:
    ///   - transfer: The validated sender, recipient, and lamport amount.
    ///   - recentBlockhash: The exact blockhash obtained from RPC.
    ///   - configuration: The explicit priority fee and resource requests.
    /// - Returns: The unsigned V1 message.
    /// - Throws: A validation error for an invalid blockhash or message.
    public func message(for transfer: Transfer, recentBlockhash: String,
                        configuration: Configuration) throws -> Data {
        try message(for: [transfer], recentBlockhash: recentBlockhash, configuration: configuration)
    }
}
