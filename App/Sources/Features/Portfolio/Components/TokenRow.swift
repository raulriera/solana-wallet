import Portfolio
import SwiftUI

/// One token in the portfolio list: its symbol and name, with its value and 24-hour change on the trailing side.
///
/// The balance takes the value's place when the value is unknown; a token without a known balance shows neither.
struct TokenRow: View {
    let symbol: String
    let name: String
    let amount: Amount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    let imageURL: URL?
    /// Whether the account also holds private SOL, which shows as a sign before the balance.
    var hasPrivateBalance = false

    var body: some View {
        // The figures sit beside the name when both fit in full, and under it otherwise, as at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                TokenRowIdentity(symbol: symbol, name: name, imageURL: imageURL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TokenRowFigures(amount: amount, value: value, change: change, hasPrivateBalance: hasPrivateBalance,
                                alignment: .trailing)
                    .layoutPriority(1)
            }
            VStack(alignment: .leading, spacing: 8) {
                TokenRowIdentity(symbol: symbol, name: name, imageURL: imageURL)
                TokenRowFigures(amount: amount, value: value, change: change, hasPrivateBalance: hasPrivateBalance,
                                alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        TokenRow(symbol: "SOL", name: "Solana", amount: Amount(units: 12_500_000_000, decimals: 9),
                 value: (total: 2_075, currency: "USD"), change: Decimal(string: "0.0129"), imageURL: nil)
        TokenRow(symbol: "MYST", name: "Mystery Token", amount: Amount(units: 42, decimals: 0), value: nil,
                 change: nil, imageURL: nil)
    }
    .listStyle(.sidebar)
}
