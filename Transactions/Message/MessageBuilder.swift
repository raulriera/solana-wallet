public import Foundation

/// A stateless encoder for V1 SOL and token transfer messages.
public struct MessageBuilder: MessageBuilding {
    /// Creates a message builder with no network, storage, or signing dependencies.
    public init() {}

    /// Encodes a V1 message with the sender as its sole signer and fee payer.
    ///
    /// Account order is sender, distinct recipient, then System Program. A transfer
    /// to the sender reuses its account index rather than duplicating the address.
    /// The blockhash is validated locally; its freshness requires an RPC check.
    ///
    /// - Parameters:
    ///   - transfer: The validated native SOL transfer.
    ///   - recentBlockhash: The exact, case-sensitive ASCII Base58 blockhash.
    ///   - configuration: The fee and resource requests to embed in the message.
    /// - Returns: The bytes to estimate fees for and sign. These are not a complete
    ///   transaction and must not be passed directly to simulation or submission.
    /// - Throws: ``ValidationError/invalidBlockhash`` if the blockhash doesn't encode 32 bytes.
    public func message(
        for transfer: Transfer,
        recentBlockhash: String,
        configuration: Configuration
    ) throws -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(2)) // SystemInstruction.transfer.
        data.appendLittleEndian(transfer.lamports)
        let instruction = MessageEncoder.Instruction(
            program: try Address("11111111111111111111111111111111"),
            accounts: [(transfer.sender, true), (transfer.recipient, true)], data: data
        )
        return try MessageEncoder.encode(payer: transfer.sender, instructions: [instruction],
                                         recentBlockhash: recentBlockhash, configuration: configuration)
    }
}
