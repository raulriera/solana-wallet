public import Foundation

/// A stateless V1 compiler shared by every program's instructions.
public struct MessageBuilder: MessageBuilding {
    /// Creates a compiler without network, storage, or signing dependencies.
    public init() {}

    /// Merges account permissions while preserving instruction and argument order.
    ///
    /// - Parameters:
    ///   - instructions: The invocations composing one atomic transaction.
    ///   - payer: The writable fee payer, placed before all other required signers.
    ///   - recentBlockhash: The exact blockhash; freshness requires an RPC check.
    ///   - configuration: The V1 fee and resource requests.
    /// - Returns: The bytes covered by every required signature.
    /// - Throws: A validation error if the composition cannot fit one V1 transaction.
    public func message(instructions: [Instruction], payer: Address, recentBlockhash: String,
                        configuration: Configuration) throws -> Data {
        try MessageEncoder.encode(payer: payer, instructions: instructions,
                                  recentBlockhash: recentBlockhash, configuration: configuration)
    }
}
