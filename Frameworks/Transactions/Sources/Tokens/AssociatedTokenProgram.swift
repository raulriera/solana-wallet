import Foundation

/// Instruction constructors for the Associated Token Account Program.
public enum AssociatedTokenProgram: Program {
    /// The Associated Token Account Program's address.
    public static let id = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

    /// Creates an instruction that creates a wallet's associated token account, and succeeds if it already exists.
    ///
    /// - Parameters:
    ///   - owner: The wallet that owns the new token account.
    ///   - mint: The mint whose tokens the account holds.
    ///   - program: The token program that owns the mint.
    ///   - payer: The account that pays the rent and signs.
    /// - Returns: The idempotent account creation instruction.
    /// - Throws: A ``ValidationError`` if a program address is invalid or the account's derivation fails.
    public static func createIdempotent(owner: Address, mint: Address, program: TokenProgram,
                                        payer: Address) throws -> Instruction {
        Instruction(program: try address, accounts: [
            .writable(payer, isSigner: true),
            .writable(try program.associatedAccount(owner: owner, mint: mint)),
            .readonly(owner),
            .readonly(mint),
            .readonly(try SystemProgram.address),
            .readonly(try program.address),
        ], data: Data([1]))
    }
}
