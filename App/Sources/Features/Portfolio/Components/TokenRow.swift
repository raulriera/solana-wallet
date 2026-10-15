import Portfolio
import SwiftUI

/// One token in the portfolio list: its symbol and name, with its value and 24-hour change on the trailing side.
///
/// The balance takes the value's place when the value is unknown; a token without a known balance shows neither.
struct TokenRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let symbol: String
    let name: String
    let amount: Amount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    let imageURL: URL?

    var body: some View {
        let isStacked = typeSize.isAccessibilitySize
        let layout = isStacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            HStack(spacing: 12) {
                TokenIcon(symbol: symbol, imageURL: imageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol)
                        .font(.headline)
                        .truncationMode(.middle)
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(isStacked ? nil : 1)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Large values and balances shorten, as in 10.2K, so the symbol and name keep their room.
            VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
                if let value {
                    TokenValue(total: value.total, currency: value.currency, abbreviates: true)
                        .font(.headline)
                    if let change {
                        DayChangeLabel(change: change)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let amount {
                    TokenBalance(amount: amount, abbreviates: true)
                        .font(.headline)
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(isStacked ? .leading : .trailing)
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
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
