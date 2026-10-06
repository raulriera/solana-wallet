import Portfolio
import SwiftUI

/// Shows an exact token quantity, keeping an unknown balance distinct from zero.
struct TokenBalance: View {
    let amount: Amount?
    var symbol: String?

    var body: some View {
        if let amount, let symbol {
            Text("\(amount, format: .amount) \(symbol)")
        } else if let amount {
            Text(amount, format: .amount)
        } else {
            Text("Unavailable")
        }
    }
}

#Preview {
    TokenBalance(amount: Amount(units: 12_500_000_000, decimals: 9), symbol: "SOL")
}
