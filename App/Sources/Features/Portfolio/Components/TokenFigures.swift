import SwiftUI
import Transactions

/// A token's value, or its balance when the value is unknown, with the 24-hour change under the value.
///
/// The fonts follow the portfolio's layout, and the private balance sign and the 24-hour change use the secondary
/// foreground style.
struct TokenFigures: View {
    @Environment(\.cardStyle.layout) private var layout
    let balance: TokenAmount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    /// Whether the account also holds the token privately.
    let isHeldPrivately: Bool

    var body: some View {
        let (valueFont, changeFont): (Font, Font) =
            switch layout {
            case .cards: (.title3.weight(.semibold), .caption.weight(.medium))
            case .rows: (.headline, .subheadline)
            }
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                if isHeldPrivately {
                    PrivateBalanceSign()
                        .foregroundStyle(.secondary)
                }
                if let value {
                    TokenValue(total: value.total, currency: value.currency, abbreviates: true)
                } else if let balance {
                    TokenBalance(balance: balance, abbreviates: true)
                }
            }
            .font(valueFont)
            if value != nil, let change {
                DayChangeLabel(change: change)
                    .font(changeFont)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}
