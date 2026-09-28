public import Foundation

/// A stateless encoder for V1 SOL and token transfer messages.
public struct MessageBuilder: MessageBuilding {
    /// Creates a message builder with no network, storage, or signing dependencies.
    public init() {}

    /// Encodes a V1 message with the sender as its sole signer and fee payer.
    ///
    /// Transfers execute in the supplied order and share one sender. Repeated
    /// recipients reuse account indices rather than duplicating addresses.
    /// The blockhash is validated locally; its freshness requires an RPC check.
    ///
    /// - Parameters:
    ///   - transfers: One or more native SOL transfers from the same sender.
    ///   - recentBlockhash: The exact, case-sensitive ASCII Base58 blockhash.
    ///   - configuration: The fee and resource requests to embed in the message.
    /// - Returns: The bytes to estimate fees for and sign. These are not a complete
    ///   transaction and must not be passed directly to simulation or submission.
    /// - Throws: A validation error for an empty list, different senders, or invalid encoding.
    public func message(
        for transfers: [Transfer],
        recentBlockhash: String,
        configuration: Configuration
    ) throws -> Data {
        guard let sender = transfers.first?.sender,
              transfers.allSatisfy({ $0.sender == sender }) else { throw ValidationError.invalidMessage }
        let program = try Address("11111111111111111111111111111111")
        let instructions = transfers.map { transfer in
            var data = Data()
            data.appendLittleEndian(UInt32(2)) // SystemInstruction.transfer.
            data.appendLittleEndian(transfer.lamports)
            return MessageEncoder.Instruction(program: program,
                accounts: [(sender, true), (transfer.recipient, true)], data: data)
        }
        return try MessageEncoder.encode(payer: sender, instructions: instructions,
                                         recentBlockhash: recentBlockhash, configuration: configuration)
    }
}
