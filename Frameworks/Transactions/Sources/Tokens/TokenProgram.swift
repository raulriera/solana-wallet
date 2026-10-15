/// The first-party Solana programs supported for token transfers.
public enum TokenProgram: String, Sendable, CaseIterable, Codable {
    /// The original SPL Token program.
    case token = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    /// The Token Extensions program, also known as Token-2022.
    case token2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
}

extension TokenProgram {
    /// The Associated Token Account program, which creates and derives each wallet's token account for a mint.
    static let associatedAccountProgram = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

    /// Derives a wallet's associated token account for a mint that this program owns.
    ///
    /// The address is the same whether or not the account exists yet.
    /// - Parameters:
    ///   - owner: The wallet that owns the token account, including an off-curve owner.
    ///   - mint: The mint whose tokens the account holds.
    /// - Returns: The canonical associated token account address.
    /// - Throws: ``TokenError/addressDerivationFailed`` if no valid bump exists.
    public func associatedAccount(owner: Address, mint: Address) throws -> Address {
        let program = try Address(rawValue)
        let associatedProgram = try Address(Self.associatedAccountProgram)
        return try ProgramAddress.find(seeds: [owner.bytes, program.bytes, mint.bytes], program: associatedProgram)
    }
}
