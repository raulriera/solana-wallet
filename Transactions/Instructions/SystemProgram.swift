import Foundation

/// Instruction constructors for Solana's System Program.
public enum SystemProgram {
    /// Creates a native SOL transfer without choosing the transaction's fee payer.
    ///
    /// - Parameters:
    ///   - sender: The writable source whose signature is required.
    ///   - recipient: The writable destination, which may equal the source.
    ///   - lamports: The positive integer amount, excluding transaction fees.
    /// - Returns: An instruction that can be composed with other program invocations.
    /// - Throws: A validation error for zero lamports or a program address used as a transfer account.
    public static func transfer(from sender: Address, to recipient: Address, lamports: UInt64) throws -> Instruction {
        guard lamports > 0 else { throw ValidationError.invalidAmount }
        let program = try Address("11111111111111111111111111111111")
        guard sender != program, recipient != program else { throw ValidationError.programAddressAsTransferAccount }
        var data = Data()
        data.appendLittleEndian(UInt32(2))
        data.appendLittleEndian(lamports)
        return Instruction(program: program, accounts: [
            .init(address: sender, isSigner: true, isWritable: true),
            .init(address: recipient, isSigner: false, isWritable: true),
        ], data: data)
    }
}
