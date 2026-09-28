/// The first-party Solana programs supported for token transfers.
public enum TokenProgram: String, Sendable, CaseIterable {
    /// The original SPL Token program.
    case token = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    /// The Token Extensions program, also known as Token-2022.
    case token2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
}
