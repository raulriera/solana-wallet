import Foundation
import Transactions

/// Saves a payment's recipient as a recent payment once the payment succeeds.
nonisolated struct RecentPaymentSettlement: TransactionSettling {
    let recents: RecentPaymentStore
    /// The address that the payment goes to.
    let recipient: Address

    func settle(_ confirmation: Confirmation) async {
        guard confirmation.outcome == .succeeded else { return }
        try? await recents.add(RecentPayment(address: recipient, date: .now), on: confirmation.submission.network)
    }
}
