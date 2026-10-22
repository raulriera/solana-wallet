import Foundation
import Portfolio
import SwiftUI

/// Shows an exact token quantity.
///
/// Abbreviated balances shorten from 10,000 up, as in 11M, while VoiceOver still reads every digit.
struct TokenBalance: View {
    let amount: Amount
    var symbol: String?
    /// Whether balances from 10,000 up are shortened, as on cards and rows.
    var abbreviates = false

    var body: some View {
        Group {
            if let symbol {
                Text("\(amount, format: .amount) \(symbol)")
            } else {
                Text(amount, format: abbreviates ? .abbreviatedAmount : .amount)
                    .accessibilityLabel(Text(amount, format: .amount))
            }
        }
        // A new balance rolls its digits into place, up or down, as values and prices do.
        .contentTransition(.numericText(value: Double(amount.units) / pow(10, Double(amount.decimals))))
    }
}

#Preview {
    TokenBalance(amount: Amount(units: 12_500_000_000, decimals: 9), symbol: "SOL")
}
