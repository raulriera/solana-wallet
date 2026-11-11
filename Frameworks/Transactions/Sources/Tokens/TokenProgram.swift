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

    /// Derives a wallet's associated token account for a mint that this program owns.
    ///
    /// - Parameters:
    ///   - owner: The wallet that owns the token account.
    ///   - mint: The mint whose tokens the account holds.
    /// - Returns: The canonical associated token account address.
    /// - Throws: ``ValidationError/addressDerivationFailed`` if no valid bump exists.
    public func associatedAccount(owner: Address, mint: Address) throws -> Address {
        try ProgramAddress.find(seeds: [owner.bytes, address.bytes, mint.bytes],
                                program: AssociatedTokenProgram.address).address
    }
}
