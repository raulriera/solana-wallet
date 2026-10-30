import Portfolio
import SwiftUI

/// Lists the wallet's tokens as native rows with selection.
struct TokenList: View {
    @Binding var selection: Holding.Identity?
    let holdings: [Holding]
    /// Whether the account also holds private SOL.
    let hasPrivateBalance: Bool

    var body: some View {
        List(holdings, selection: $selection) { holding in
            TokenRow(symbol: holding.displaySymbol, name: holding.displayName, amount: holding.amount,
                     value: holding.knownValue, change: holding.valuation?.dayChange, imageURL: holding.logoURL,
                     hasPrivateBalance: hasPrivateBalance && holding.id == .nativeSOL)
        }
        .listStyle(.sidebar)
    }
}
