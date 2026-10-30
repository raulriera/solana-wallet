import Portfolio
import SwiftUI

/// A token row's value, or its balance when the value is unknown, with the 24-hour change under the value.
struct TokenRowFigures: View {
    let amount: Amount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    /// Whether the account also holds private SOL.
    let hasPrivateBalance: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                if hasPrivateBalance {
                    PrivateBalanceSign()
                        .foregroundStyle(.secondary)
                }
                if let value {
                    TokenValue(total: value.total, currency: value.currency, abbreviates: true)
                } else if let amount {
                    TokenBalance(amount: amount, abbreviates: true)
                }
            }
            .font(.headline)
            if value != nil, let change {
                DayChangeLabel(change: change)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}
