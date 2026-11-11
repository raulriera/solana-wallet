import Foundation

extension TokenTransfer {
    /// Returns the instructions that perform the transfer.
    ///
    /// - Returns: The account creation, memo, and checked-transfer instructions, in order.
    /// - Throws: A ``ValidationError`` if a program identifier is invalid or the new account's derivation fails.
    public func instructions() throws -> [Instruction] {
        let transfer = self
        let program = try transfer.mint.program.address
        var instructions: [Instruction] = []
        if transfer.createsDestination {
            instructions.append(try transfer.mint.program.createAssociatedAccount(
                owner: transfer.recipient, mint: transfer.mint.address, payer: transfer.sender
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
