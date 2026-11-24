import SwiftUI
import Transactions

/// Shows an asset's available and pending private amounts with their actions, or a failed read with a Try Again button.
struct PrivateBalanceAmountSection: View {
    @State private var isRefreshing = false
    /// The spendable private balance, or `nil` without a balance.
    let available: TokenAmount?
    /// The private balance the network hasn't reported yet, or `nil` without a balance.
    let pending: TokenAmount?
    let asset: Asset
    /// Whether the last read failed.
    let isStale: Bool
    /// The action that reads the balance again, or `nil` where nothing can.
    let refresh: RefreshAction?

    var body: some View {
        Section {
            if let available {
                LabeledContent("Available") {
                    TokenBalance(balance: available, asset: asset)
                        .textSelection(.enabled)
                }
            }
            if let pending, pending.amount > 0 {
                LabeledContent("Pending") {
                    TokenBalance(balance: pending, asset: asset)
                }
            }
            if isStale {
                Label("Couldn't update", systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.warning)
                Button {
                    Task {
                        isRefreshing = true
                        await refresh?()
                        isRefreshing = false
                    }
                } label: {
                    PendingLabel(title: "Try Again", isPending: isRefreshing)
                }
                .disabled(isRefreshing)
            } else if let available {
                PrivateBalanceActions(available: available, asset: asset)
            }
        } header: {
            Text("Private Balance")
        }
    }
}
