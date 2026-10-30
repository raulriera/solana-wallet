/// An error from reading token accounts or building a token transfer.
public enum TokenError: Error, Sendable, Equatable {
    case unsupportedProgram
    case invalidAccount
    /// The mint, program, authority, or destination doesn't match the transfer.
    case accountMismatch
    case insufficientBalance
    case frozenAccount
    case transferDisabled
    /// An extension, by type number, whose transfer requirements aren't supported.
    case unsupportedExtension(UInt16)
    /// A fee-bearing transfer needs the current epoch.
    case epochRequired
    case memoRequired
    /// The memo doesn't fit in a V1 transaction.
    case invalidMemo
}
