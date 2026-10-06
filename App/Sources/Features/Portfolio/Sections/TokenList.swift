import Portfolio
import SwiftUI

/// Lists the wallet's tokens with native selection and says when the shown balances may be out of date.
struct TokenList: View {
    @Binding var selection: Holding.Identity?
    let holdings: [Holding]
    let failure: PortfolioFailure?

    var body: some View {
        List(holdings, selection: $selection) { holding in
            TokenRow(holding: holding)
        }
        .listStyle(.sidebar)
        .navigationTitle("Portfolio")
        .navigationSubtitle(Text(status ?? ""))
    }

    /// Why the shown balances may be out of date, or `nil` after a successful refresh.
    private var status: LocalizedStringResource? {
        switch failure {
        case .rateLimited: "Too many requests"
        case .unavailable: "Couldn't update balances"
        case .missingKey, .invalidKey, nil: nil
        }
    }
}
