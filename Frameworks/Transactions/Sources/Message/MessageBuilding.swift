public import Foundation

/// A type that compiles ordered instructions into a bounded V1 message.
public protocol MessageBuilding: Sendable {
    /// Compiles one atomic transaction without signing or networking.
    ///
    /// - Parameters:
    ///   - instructions: Program invocations in execution order.
    ///   - payer: The writable signer paying network fees, independent of instruction authorities.
    ///   - recentBlockhash: The exact Base58 lifetime value to encode.
    ///   - configuration: The explicit V1 fee and resource requests.
    /// - Returns: Message bytes, excluding the required signature slots.
    /// - Throws: A validation error for invalid roles, blockhash, or transaction limits.
    func message(instructions: [Instruction], payer: Address, recentBlockhash: String,
                 configuration: Configuration) throws -> Data
}
