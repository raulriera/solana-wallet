import Foundation

extension MessageEncoder.Instruction {
    /// Encodes a System Program transfer for a payment or service tip.
    ///
    /// - Parameter transfer: The validated sender, recipient, and lamport amount.
    /// - Throws: A validation error if the System Program address is invalid.
    init(transfer: Transfer) throws {
        var data = Data()
        data.appendLittleEndian(UInt32(2)) // SystemInstruction.transfer.
        data.appendLittleEndian(transfer.lamports)
        self.init(program: try Address("11111111111111111111111111111111"),
                  accounts: [(transfer.sender, true), (transfer.recipient, true)], data: data)
    }
}
