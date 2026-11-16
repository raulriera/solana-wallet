import Portfolio
import SwiftUI
import Transactions

/// Lists the wallet's tokens as native rows with selection.
struct TokenList: View {
    @Binding var selection: Asset.ID?
    let holdings: [Holding]
    /// The holdings that the account also holds privately.
    let privateHoldings: Set<Asset.ID>

    var body: some View {
        List(holdings, selection: $selection) { holding in
            TokenRow(symbol: holding.asset.displaySymbol, name: holding.asset.displayName, balance: holding.balance,
                     value: holding.knownValue, change: holding.valuation?.dayChange, imageURL: holding.logoURL,
                     isHeldPrivately: privateHoldings.contains(holding.id))
        }
        .listStyle(.sidebar)
    }
}
