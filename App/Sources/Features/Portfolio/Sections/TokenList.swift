import Portfolio
import SwiftUI

/// Lists the wallet's tokens as native rows with selection.
struct TokenList: View {
    @Binding var selection: Holding.Identity?
    let holdings: [Holding]

    var body: some View {
        List(holdings, selection: $selection) { holding in
            TokenRow(holding: holding)
        }
        .listStyle(.sidebar)
    }
}
