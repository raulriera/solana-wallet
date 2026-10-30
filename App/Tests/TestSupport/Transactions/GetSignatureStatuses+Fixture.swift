@testable import RPC

extension GetSignatureStatuses.Response {
    nonisolated static func status(_ commitment: Commitment?, error: TransactionError? = nil) -> Self {
        let status = commitment.map {
            GetSignatureStatuses.Status(slot: 405, confirmations: nil, error: error, confirmationStatus: $0)
        }
        return Self(context: Context(slot: 2_000), value: [status])
    }
}
