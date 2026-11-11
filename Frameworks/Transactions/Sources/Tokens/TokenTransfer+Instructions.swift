import Foundation

extension TokenTransfer {
    /// Returns the instructions that perform the transfer.
    ///
    /// - Returns: The account creation, memo, and checked-transfer instructions, in order.
    /// - Throws: A ``ValidationError`` if a program address is invalid or the destination's derivation fails.
    public func instructions() throws -> [Instruction] {
        var instructions: [Instruction] = []
        if createsDestination {
            instructions.append(try AssociatedTokenProgram.createIdempotent(
                owner: recipient, mint: mint.address, program: mint.program, payer: sender))
        }
        if let memo {
            instructions.append(try MemoProgram.memo(memo, signers: [sender]))
        }
        instructions.append(try mint.program.transferChecked(
            amount, decimals: mint.decimals, from: source.address, mint: mint.address,
            to: destination, authority: sender, fee: expectedFee))
        return instructions
    }
}
