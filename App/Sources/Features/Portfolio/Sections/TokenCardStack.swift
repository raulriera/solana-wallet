import Portfolio
import SwiftUI

/// Lists the wallet's tokens as overlapping cards tucked into a pocket; choosing a card shows its details.
struct TokenCardStack: View {
    @Environment(\.palette) private var palette
    @Binding var selection: Holding.Identity?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let holdings: [Holding]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(holdings) { holding in
                    TokenCardOption(selection: $selection, preferredColumn: $preferredColumn, id: holding.id) {
                        TokenCard(symbol: holding.displaySymbol, name: holding.displayName, amount: holding.amount,
                                  value: holding.knownValue, change: holding.valuation?.dayChange,
                                  imageURL: holding.imageURL)
                    }
                    .padding(.horizontal, 12)
                }
                // The pocket follows the last card and covers the lower part of the cards.
                CardPocket()
                    .padding(.top, 24)
            }
            .padding(.top, 8)
        }
        .background(palette.surface)
    }
}
