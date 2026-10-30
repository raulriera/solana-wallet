import Portfolio
import SwiftUI

/// Lists the wallet's tokens as overlapping cards tucked into a pocket.
struct TokenCardStack: View {
    @Binding var selection: Holding.Identity?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let holdings: [Holding]
    /// Whether the account also holds private SOL.
    let hasPrivateBalance: Bool

    var body: some View {
        List {
            VStack(spacing: 0) {
                ForEach(holdings) { holding in
                    TokenCardOption(selection: $selection, preferredColumn: $preferredColumn, id: holding.id) {
                        TokenCard(symbol: holding.displaySymbol, name: holding.displayName, amount: holding.amount,
                                  value: holding.knownValue, change: holding.valuation?.dayChange,
                                  imageURL: holding.logoURL,
                                  hasPrivateBalance: hasPrivateBalance && holding.id == .nativeSOL)
                    }
                }
            }
            .padding(.bottom, 24)
            .clipShape(PocketClip())
            .padding(.top, 20)
            .padding(.bottom, 120)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
    }
}
