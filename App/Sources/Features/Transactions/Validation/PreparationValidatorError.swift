/// An operation prerequisite that requires a new preparation or user review.
nonisolated enum PreparationValidatorError: Error, Sendable, Equatable {
    /// The selected provider serves a different network from the reviewed preparation.
    case networkMismatch
    /// The encoded message differs from the reviewed inspection or local instruction composition.
    case messageMismatch
    /// Simulation reported that the transaction couldn't execute.
    case simulationFailed
    /// The preparation has no known network fee to review.
    case feeUnavailable
    /// The simulation, fee, or ledger contexts conflict with the prepared message.
    case inconsistentPreparation
    /// The provider can no longer confirm the reviewed total fee.
    case feeChanged
    /// The original blockhash has expired or its current validity can't be established.
    case expired
}
