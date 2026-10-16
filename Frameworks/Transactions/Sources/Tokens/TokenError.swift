/// A token construction failure that never includes account data in diagnostics.
public enum TokenError: Error, Sendable, Equatable {
    /// The account is not owned by either supported token program.
    case unsupportedProgram
    /// The base account data or extension framing is malformed.
    case invalidAccount
    /// The mint, program, authority, or destination doesn't match the transfer.
    case accountMismatch
    /// The source token account doesn't contain the requested amount.
    case insufficientBalance
    /// A source or destination account is frozen, including a new account's default state.
    case frozenAccount
    /// The mint forbids transfers or currently pauses them.
    case transferDisabled
    /// Construction doesn't implement the extension's transfer requirements.
    case unsupportedExtension(UInt16)
    /// Fee-bearing transfers require the ledger epoch used to select the fee schedule.
    case epochRequired
    /// The destination requires a nonempty memo immediately before the transfer.
    case memoRequired
    /// The memo cannot fit within the maximum V1 transaction size.
    case invalidMemo
}
