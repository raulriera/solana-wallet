import Foundation

/// Instruction constructors for the System Program.
public enum SystemProgram {
    /// The System Program's address.
    static let id = "11111111111111111111111111111111"

    /// The program's address.
    public static var address: Address {
        get throws { try Address(id) }
    }

    /// Creates a native SOL transfer instruction.
    ///
    /// - Parameters:
    ///   - sender: The account that sends and signs.
    ///   - recipient: The account that receives.
    ///   - lamports: The amount in lamports, greater than zero.
    /// - Returns: The transfer instruction.
    /// - Throws: A validation error for zero lamports or a program address used as a transfer account.
    public static func transfer(from sender: Address, to recipient: Address, lamports: UInt64) throws -> Instruction {
        guard lamports > 0 else { throw ValidationError.invalidAmount }
        let program = try address
        guard sender != program, recipient != program else { throw ValidationError.programAddressAsTransferAccount }
        var data = Data()
        data.appendLittleEndian(UInt32(2))
        data.appendLittleEndian(lamports)
        return Instruction(program: program, accounts: [
            .writable(sender, isSigner: true),
            .writable(recipient),
        ], data: data)
    }
}
