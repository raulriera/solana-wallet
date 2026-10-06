import Portfolio
import SwiftUI

/// One token in the portfolio list: its symbol and name, with its balance and known value on the trailing side.
struct TokenRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let holding: Holding

    var body: some View {
        let isStacked = typeSize.isAccessibilitySize
        let layout = isStacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            HStack(spacing: 12) {
                TokenIcon(symbol: holding.displaySymbol, imageURL: holding.imageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.displaySymbol)
                        .font(.headline)
                        .truncationMode(.middle)
                    Text(holding.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(isStacked ? nil : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Exact amounts never truncate; the name gives way first.
            VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
                TokenBalance(amount: holding.amount)
                    .font(.headline)
                if let value = holding.knownValue {
                    Text(value.total, format: .currency(code: value.currency))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        TokenRow(holding: Holding(id: .nativeSOL, amount: Amount(units: 12_500_000_000, decimals: 9), name: "Solana",
                                  symbol: "SOL", imageURL: nil,
                                  valuation: Valuation(pricePerUnit: 166, total: 2_075, currency: "USD")))
        TokenRow(holding: Holding(id: .asset("mint"), amount: Amount(units: 42, decimals: 0), name: "Mystery Token",
                                  symbol: "MYST", imageURL: nil, valuation: nil))
    }
    .listStyle(.sidebar)
}
