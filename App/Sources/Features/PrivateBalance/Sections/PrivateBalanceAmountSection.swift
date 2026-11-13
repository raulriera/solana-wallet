import Portfolio
import SwiftUI

/// Shows an asset's available and pending private amounts with their actions, or a failed read with a Try Again button.
struct PrivateBalanceAmountSection: View {
    @Environment(\.palette) private var palette
    @State private var isRefreshing = false
    /// The spendable private balance, or `nil` without a balance.
    let available: Amount?
    /// The private balance the network hasn't reported yet, or `nil` without a balance.
    let pending: Amount?
    let symbol: String
    /// Whether the last read failed.
    let isStale: Bool
    /// The action that reads the balance again, or `nil` where nothing can.
    let refresh: RefreshAction?

    var body: some View {
        Section {
            if let available {
                LabeledContent("Available") {
                    TokenBalance(amount: available, symbol: symbol)
                        .textSelection(.enabled)
                }
            }
            if let pending, pending.units > 0 {
                LabeledContent("Pending") {
                    TokenBalance(amount: pending, symbol: symbol)
                        .foregroundStyle(palette.secondaryText)
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
                .foregroundStyle(palette.primary)
                .disabled(isRefreshing)
            } else if let available {
                PrivateBalanceActions(available: available, symbol: symbol)
            }
        } header: {
            Text("Private Balance")
        } footer: {
            if !isStale, let pending, pending.units > 0 {
                Text("Pending \(symbol) becomes available when the network reports it, usually within a minute.",
                     comment: "Footer under a private balance with a pending amount, such as a recent deposit. The variable is the token's symbol, such as SOL or USDC.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }
}
