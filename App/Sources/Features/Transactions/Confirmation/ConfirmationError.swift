import RPC

/// Why the check of a sent transaction stopped before the transaction settled.
nonisolated enum ConfirmationError: Error {
    case rateLimited
    /// The provider refused the API key.
    case invalidKey
    /// The provider can't check the transaction.
    case unavailable

    /// Creates the reason from the error that stopped the check.
    ///
    /// - Parameter error: The error that stopped the check.
    init(_ error: any Error) {
        switch error {
        case let error as RPCError where error.isRateLimited: self = .rateLimited
        case let error as RPCError where error.rejectsKey: self = .invalidKey
        default: self = .unavailable
        }
    }
}
