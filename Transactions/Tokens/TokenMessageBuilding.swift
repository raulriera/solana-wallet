public import Foundation

/// A type that constructs V1 token messages without networking, signing, or storage.
public protocol TokenMessageBuilding: Sendable {
    /// Encodes account creation, any memo, and a checked token transfer in order.
    ///
    /// - Parameters:
    ///   - transfer: The account-validated transfer for either token program.
    ///   - recentBlockhash: The exact Base58 blockhash to include in the message.
    ///   - configuration: The V1 fee and resource limits to validate by simulation.
    /// - Returns: Unsigned message bytes accepted by the existing transaction assembler.
    /// - Throws: ``ValidationError`` for an invalid blockhash or message size.
    func message(for transfer: TokenTransfer, recentBlockhash: String, configuration: Configuration) throws -> Data
}
