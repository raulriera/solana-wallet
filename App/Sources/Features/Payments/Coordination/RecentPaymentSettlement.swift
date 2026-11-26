import Foundation
import Transactions

/// Saves a payment's recipient as a recent payment once the payment succeeds.
nonisolated struct RecentPaymentSettlement: TransactionSettling {
    let recents: RecentPaymentStore
    let recipient: Address

    func settle(_ outcome: TransactionOutcome) async {
        guard case .succeeded = outcome.status else { return }
        try? await recents.add(RecentPayment(address: recipient, date: .now), on: outcome.network)
    }
}
