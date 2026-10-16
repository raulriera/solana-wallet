/// Public devnet addresses with Solana Rings activity, for read-only live tests; their keys aren't available.
///
/// Found read-only on 2026-10-16: `getSignaturesForAddress` on the shielded-pool program
/// `sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6` at the public devnet RPC, then `getTransaction` on its
/// recent transactions. Each owner paid for a deposit (tag 15) to its own view tag, and the first also sent a
/// transact (tag 16). All four hold 134-byte user-registry records (`getProgramAccounts` on
/// `regyS5rkAcw2YzDJCmTwCTHs2s246FXxbmuRZ42u2PD`).
enum ShieldedPoolOwners {
    /// The owners' base-58 addresses, whose Ed25519 public keys are their view tags.
    static let devnet = [
        "FVzg3KzZGudAbj9S7DuvXsryACrL6XSF5gb5FTPpBTZW",
        "7bACPtzxZANLtm8M6E5ovGrftXvcdia9qokkUwWSWBaW",
        "3VtwQ5NpmfWfMusP2P1qENpFyYYFaUyXkbjDyuaiHXva",
        "AHUWkkufV4h1fPNyWAxwrzvTBYUeaGfpa8ygjz8X6vTQ",
    ]
}
