public import Foundation

/// A type that compiles ordered instructions into a V1 message.
public protocol MessageBuilding: Sendable {
    /// Compiles instructions into a V1 message.
    ///
    /// - Parameters:
    ///   - instructions: The instructions in execution order.
    ///   - payer: The signer that pays network fees.
    ///   - recentBlockhash: The recent blockhash, in Base58.
    ///   - configuration: The fee and resource requests.
    /// - Returns: The message bytes, without signature slots.
    /// - Throws: A validation error for invalid roles, blockhash, or transaction limits.
    func message(instructions: [Instruction], payer: Address, recentBlockhash: String,
                 configuration: Configuration) throws -> Data
}
