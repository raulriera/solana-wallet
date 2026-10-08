import Portfolio
import SwiftUI

/// Lists the wallet's tokens as overlapping cards tucked into a pocket; choosing a card shows its details.
///
/// The cards sit in a sidebar list, so the system draws the same background as in every other sidebar.
struct TokenCardStack: View {
    @Binding var selection: Holding.Identity?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let holdings: [Holding]

    var body: some View {
        List {
            // One row keeps the cards overlapping; separate rows clip each card on compact displays.
            VStack(spacing: 0) {
                ForEach(holdings) { holding in
                    TokenCardOption(selection: $selection, preferredColumn: $preferredColumn, id: holding.id) {
                        TokenCard(symbol: holding.displaySymbol, name: holding.displayName, amount: holding.amount,
                                  value: holding.knownValue, change: holding.valuation?.dayChange,
                                  imageURL: holding.imageURL)
                    }
                    .padding(.horizontal, 12)
                }
            }
            // The cards end at the pocket's lip below the last card, so the sidebar shows through the pocket.
            .padding(.bottom, 24)
            .clipShape(PocketClip())
            // The row clips its content, so the first card's lift and shadow need room above it.
            .padding(.top, 20)
            .padding(.bottom, 120)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        // The cards keep their own margins; the list's margins would narrow them.
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}
