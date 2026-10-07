import Portfolio
import SwiftUI

/// Shows an exact token quantity, keeping an unknown balance distinct from zero.
///
/// Abbreviated balances shorten from 10,000 up, as in 11M, while VoiceOver still reads every digit.
struct TokenBalance: View {
    let amount: Amount?
    var symbol: String?
    /// Whether balances from 10,000 up are shortened, as on cards and rows.
    var abbreviates = false

    var body: some View {
        if let amount, let symbol {
            Text("\(amount, format: .amount) \(symbol)")
        } else if let amount {
            Text(amount, format: abbreviates ? .abbreviatedAmount : .amount)
                .accessibilityLabel(Text(amount, format: .amount))
        } else {
            Text("Unavailable")
        }
    }
}

#Preview {
    TokenBalance(amount: Amount(units: 12_500_000_000, decimals: 9), symbol: "SOL")
}
