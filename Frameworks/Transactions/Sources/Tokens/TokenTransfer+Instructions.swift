import Foundation

extension TokenTransfer {
    /// Returns the instructions that perform the transfer.
    ///
    /// - Returns: The account creation, memo, and checked-transfer instructions, in order.
    /// - Throws: An address validation error if a program identifier is invalid.
    public func instructions() throws -> [Instruction] {
        let transfer = self
        let program = try transfer.mint.program.address
        var instructions: [Instruction] = []
        if transfer.createsDestination {
            instructions.append(.init(
                program: try Address(TokenProgram.associatedAccountProgram),
                accounts: [.init(address: transfer.sender, isSigner: true, isWritable: true),
                           .init(address: transfer.destination, isSigner: false, isWritable: true),
                           .init(address: transfer.recipient, isSigner: false, isWritable: false),
                           .init(address: transfer.mint.address, isSigner: false, isWritable: false),
                           .init(address: try Address(SystemProgram.id), isSigner: false, isWritable: false),
                           .init(address: program, isSigner: false, isWritable: false)], data: Data([1])
            ))
        }
        if let memo = transfer.memo {
            instructions.append(try MemoProgram.memo(memo, signers: [transfer.sender]))
        }
        var payload = Data(transfer.expectedFee == nil ? [12] : [26, 1])
        payload.appendLittleEndian(transfer.amount)
        payload.append(transfer.mint.decimals)
        if let fee = transfer.expectedFee { payload.appendLittleEndian(fee) }
        instructions.append(.init(program: program,
                                  accounts: [.init(address: transfer.source.address, isSigner: false, isWritable: true),
                                             .init(address: transfer.mint.address, isSigner: false, isWritable: false),
                                             .init(address: transfer.destination, isSigner: false, isWritable: true),
                                             .init(address: transfer.sender, isSigner: true, isWritable: false)], data: payload))
        return instructions
    }
}
