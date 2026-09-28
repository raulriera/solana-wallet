public import Foundation

/// A type that constructs V1 token messages without networking, signing, or storage.
public protocol TokenMessageBuilding: Sendable {
    /// Encodes account creation, any memo, a checked token transfer, and service tips in order.
    ///
    /// - Parameters:
    ///   - transfer: The account-validated transfer for either token program.
    ///   - tips: Native SOL payments sharing the token transfer's sender and fee payer.
    ///   - recentBlockhash: The exact Base58 blockhash to include in the message.
    ///   - configuration: The V1 fee and resource limits to validate by simulation.
    /// - Returns: Unsigned message bytes accepted by the existing transaction assembler.
    /// - Throws: ``ValidationError`` for a different tip payer, invalid blockhash, or message size.
    func message(for transfer: TokenTransfer, tips: [Transfer], recentBlockhash: String,
                 configuration: Configuration) throws -> Data
}

extension TokenMessageBuilding {
    /// Encodes a token transfer without additional service payments.
    ///
    /// - Parameters:
    ///   - transfer: The account-validated token transfer.
    ///   - recentBlockhash: The exact blockhash to include.
    ///   - configuration: The explicit fee and resource limits.
    /// - Returns: The unsigned V1 message.
    /// - Throws: A construction or encoding error.
    public func message(for transfer: TokenTransfer, recentBlockhash: String,
                        configuration: Configuration) throws -> Data {
        try message(for: transfer, tips: [], recentBlockhash: recentBlockhash, configuration: configuration)
    }
}
