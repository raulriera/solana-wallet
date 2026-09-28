import Foundation

extension TokenTransfer {
    /// Constructs a token transfer for either program using their shared wire layout.
    ///
    /// Destination creation is idempotent, so another sender creating the account
    /// before execution doesn't invalidate the instruction. Token-2022 fees are
    /// checked on-chain; a changed fee requires a new preparation and approval.
    ///
    /// - Parameters:
    ///   - payer: The account paying any destination creation deposit; defaults to the token owner.
    /// - Returns: Ordered account creation, memo, and checked-transfer instructions.
    /// - Throws: An address validation error if a program identifier is invalid.
    public func instructions(payer: Address? = nil) throws -> [Instruction] {
        let transfer = self
        let payer = payer ?? sender
        let program = try Address(transfer.mint.program.rawValue)
        var instructions: [Instruction] = []
        if transfer.createsDestination {
            instructions.append(.init(
                program: try Address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
                accounts: [.init(address: payer, isSigner: true, isWritable: true),
                           .init(address: transfer.destination, isSigner: false, isWritable: true),
                           .init(address: transfer.recipient, isSigner: false, isWritable: false),
                           .init(address: transfer.mint.address, isSigner: false, isWritable: false),
                           .init(address: try Address("11111111111111111111111111111111"), isSigner: false, isWritable: false),
                           .init(address: program, isSigner: false, isWritable: false)], data: Data([1]) // CreateIdempotent.
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
