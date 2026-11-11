import Foundation

/// A token program, with its address as the raw value.
public enum TokenProgram: String, Sendable, CaseIterable, Codable {
    /// The SPL Token program.
    case token = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    case token2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
}

extension TokenProgram {
    /// The program's address.
    public var address: Address {
        get throws { try Address(rawValue) }
    }

    /// The Associated Token Account program's address.
    static let associatedAccountProgram = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

    /// Derives a wallet's associated token account for a mint that this program owns.
    ///
    /// - Parameters:
    ///   - owner: The wallet that owns the token account.
    ///   - mint: The mint whose tokens the account holds.
    /// - Returns: The canonical associated token account address.
    /// - Throws: ``ValidationError/addressDerivationFailed`` if no valid bump exists.
    public func associatedAccount(owner: Address, mint: Address) throws -> Address {
        let program = try address
        let associatedProgram = try Address(Self.associatedAccountProgram)
        return try ProgramAddress.find(seeds: [owner.bytes, program.bytes, mint.bytes], program: associatedProgram).address
    }

    /// Creates the instruction that opens a wallet's associated token account for a mint that this program owns, and
    /// that succeeds without a change when the account already exists.
    ///
    /// - Parameters:
    ///   - owner: The wallet that owns the token account.
    ///   - mint: The mint whose tokens the account holds.
    ///   - payer: The account that signs and pays the new account's rent.
    /// - Returns: The Associated Token Account program's idempotent create instruction.
    /// - Throws: A ``ValidationError`` if a program address is invalid or no valid bump exists.
    public func createAssociatedAccount(owner: Address, mint: Address, payer: Address) throws -> Instruction {
        try Instruction(program: Address(Self.associatedAccountProgram), accounts: [
            .init(address: payer, isSigner: true, isWritable: true),
            .init(address: associatedAccount(owner: owner, mint: mint), isSigner: false, isWritable: true),
            .init(address: owner, isSigner: false, isWritable: false),
            .init(address: mint, isSigner: false, isWritable: false),
            .init(address: Address(SystemProgram.id), isSigner: false, isWritable: false),
            .init(address: address, isSigner: false, isWritable: false),
        ], data: Data([1]))
    }
}
