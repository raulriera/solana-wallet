import Portfolio
import SwiftUI
import Transactions

/// Lists the wallet's tokens as overlapping cards tucked into a pocket.
struct TokenCardStack: View {
    @Binding var selection: Asset.ID?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let holdings: [Holding]
    /// The holdings that the account also holds privately.
    let privateHoldings: Set<Asset.ID>

    var body: some View {
        List {
            VStack(spacing: 0) {
                ForEach(holdings) { holding in
                    TokenCardOption(selection: $selection, preferredColumn: $preferredColumn, id: holding.id) {
                        TokenCard(symbol: holding.asset.displaySymbol, name: holding.asset.displayName,
                                  balance: holding.balance, value: holding.knownValue,
                                  change: holding.valuation?.dayChange, imageURL: holding.logoURL,
                                  isHeldPrivately: privateHoldings.contains(holding.id))
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
