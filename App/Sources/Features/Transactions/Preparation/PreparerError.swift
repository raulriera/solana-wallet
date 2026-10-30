/// An error for a transaction or configuration that can't be prepared.
nonisolated enum PreparerError: Error, Sendable, Equatable {
    case invalidBlockhash
    case priorityFeeTooLow(minimumLamports: UInt64)
    /// The provider's responses conflict with the request or are out of range.
    case inconsistentResponse
    case resourceUsageUnavailable
}
