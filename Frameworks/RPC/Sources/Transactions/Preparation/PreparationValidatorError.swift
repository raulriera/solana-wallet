/// An error for a preparation that must be prepared and reviewed again.
public enum PreparationValidatorError: Error, Sendable, Equatable {
    /// The encoded message differs from the reviewed one.
    case messageMismatch
    case simulationFailed
    case feeUnavailable
    /// The simulation, fee, or ledger context conflicts with the message.
    case inconsistentPreparation
    case feeChanged
    /// The blockhash expired, or its validity is unknown.
    case expired
}
