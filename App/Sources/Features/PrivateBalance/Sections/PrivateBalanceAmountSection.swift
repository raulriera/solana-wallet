import Portfolio
import SwiftUI

/// Shows an asset's available and pending private amounts with their actions, or only the footer without a balance.
struct PrivateBalanceAmountSection: View {
    @Environment(\.palette) private var palette
    /// The spendable private balance, or `nil` without a balance.
    let available: Amount?
    /// The private balance the network hasn't reported yet, or `nil` without a balance.
    let pending: Amount?
    let symbol: String
    /// Whether the last read failed.
    let isStale: Bool

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
            if let available {
                PrivateBalanceActions(available: available, symbol: symbol)
                    .disabled(isStale)
            }
        } header: {
            Text("Private Balance")
        } footer: {
            Group {
                if isStale {
                    Text("Couldn't update private balance.",
                         comment: "Footer under a private balance that the last read couldn't update, such as when a network request fails. The balance shown is the last one read or saved, if any.")
                } else if let pending, pending.units > 0 {
                    Text("Pending \(symbol) becomes available when the network reports it, usually within a minute.",
                         comment: "Footer under a private balance with a pending amount, such as a recent deposit. The variable is the token's symbol, such as SOL or USDC.")
                }
            }
            .foregroundStyle(palette.secondaryText)
        }
    }
}
