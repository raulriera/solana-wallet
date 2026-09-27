import Encoding
public import Foundation

/// A stateless encoder for single-instruction V1 SOL transfer messages.
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
        guard let blockhash = Base58.decode(recentBlockhash, byteCount: 32) else {
            throw ValidationError.invalidBlockhash
        }
        let sendsToSelf = transfer.sender == transfer.recipient
        let programIndex: UInt8 = sendsToSelf ? 1 : 2
        let recipientIndex: UInt8 = sendsToSelf ? 0 : 1

        // Version, one writable signer, no read-only signers, one read-only program.
        var message = Data([0x81, 1, 0, 1])
        let configurationMask: UInt32 = configuration.heapSize == nil ? 0x0f : 0x1f
        message.appendLittleEndian(configurationMask)
        message.append(contentsOf: blockhash)
        message.append(contentsOf: [1, programIndex + 1])
        message.append(contentsOf: transfer.sender.bytes)
        if !sendsToSelf { message.append(contentsOf: transfer.recipient.bytes) }
        message.append(contentsOf: repeatElement(UInt8(0), count: 32)) // System Program.

        message.appendLittleEndian(configuration.priorityFeeLamports)
        message.appendLittleEndian(configuration.computeUnitLimit)
        message.appendLittleEndian(configuration.loadedAccountsDataSizeLimit)
        if let heapSize = configuration.heapSize { message.appendLittleEndian(heapSize) }

        // Instruction header: program index, two accounts, twelve data bytes.
        message.append(contentsOf: [programIndex, 2])
        message.appendLittleEndian(UInt16(12))
        message.append(contentsOf: [0, recipientIndex])
        message.appendLittleEndian(UInt32(2)) // SystemInstruction.transfer discriminant.
        message.appendLittleEndian(transfer.lamports)
        return message
    }
}
