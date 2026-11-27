/// An error for a transaction or configuration that can't be prepared.
public enum PreparerError: Error, Sendable, Equatable {
    case invalidBlockhash
    case priorityFeeTooLow(minimumLamports: UInt64)
    /// The provider's block height leaves no representable expiry.
    case expiryOutOfRange
    case resourceUsageUnavailable
}
