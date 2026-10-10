/// A preparation requirement that the supplied transaction or configuration doesn't meet.
nonisolated enum PreparerError: Error, Sendable, Equatable {
    /// The node cannot confirm the supplied value as a valid recent blockhash.
    case invalidBlockhash
    /// The selected submission service requires a larger reviewed priority fee.
    case priorityFeeTooLow(minimumLamports: UInt64)
    /// Provider observations conflict with the requested ledger context or exact message.
    case inconsistentResponse
    /// The provider omitted the resource usage needed to estimate V1 limits.
    case resourceUsageUnavailable
}
