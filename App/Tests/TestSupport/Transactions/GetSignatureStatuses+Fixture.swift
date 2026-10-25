@testable import RPC

extension GetSignatureStatuses.Response {
    /// Wraps one transaction's status in a status read at slot 2,000.
    /// - Parameters:
    ///   - commitment: The status's commitment at slot 405, or `nil` when the provider has no status.
    ///   - error: The landed transaction's execution error, or `nil` when it succeeded.
    /// - Returns: A one-signature status read.
    nonisolated static func status(_ commitment: Commitment?, error: TransactionError? = nil) -> Self {
        let status = commitment.map {
            GetSignatureStatuses.Status(slot: 405, confirmations: nil, error: error, confirmationStatus: $0)
        }
        return Self(context: Context(slot: 2_000), value: [status])
    }
}
