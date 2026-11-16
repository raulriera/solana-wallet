import SwiftUI
import Transactions

/// One token in the portfolio list: its symbol and name, with its value and 24-hour change on the trailing side.
struct TokenRow: View {
    let symbol: String
    let name: String
    let balance: TokenAmount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    let imageURL: URL?
    /// Whether the account also holds the token privately.
    var isHeldPrivately = false

    var body: some View {
        HStack(spacing: 12) {
            TokenRowIdentity(symbol: symbol, name: name, imageURL: imageURL)
                .frame(maxWidth: .infinity, alignment: .leading)
            TokenRowFigures(balance: balance, value: value, change: change, isHeldPrivately: isHeldPrivately)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        TokenRow(symbol: "SOL", name: "Solana", balance: TokenAmount(amount: 12_500_000_000, decimals: 9),
                 value: (total: 2_075, currency: "USD"), change: Decimal(string: "0.0129"), imageURL: nil)
        TokenRow(symbol: "MYST", name: "Mystery Token", balance: TokenAmount(amount: 42, decimals: 0), value: nil,
                 change: nil, imageURL: nil)
    }
    .listStyle(.sidebar)
}
