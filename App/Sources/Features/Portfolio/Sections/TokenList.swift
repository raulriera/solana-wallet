import Portfolio
import SwiftUI

/// Lists the wallet's tokens as native rows with selection.
struct TokenList: View {
    @Binding var selection: Holding.Identity?
    let holdings: [Holding]
    /// The holdings that the account also holds privately.
    let privateHoldings: Set<Holding.Identity>

    var body: some View {
        List(holdings, selection: $selection) { holding in
            TokenRow(symbol: holding.displaySymbol, name: holding.displayName, amount: holding.amount,
                     value: holding.knownValue, change: holding.valuation?.dayChange, imageURL: holding.logoURL,
                     isHeldPrivately: privateHoldings.contains(holding.id))
        }
        .listStyle(.sidebar)
    }
}
