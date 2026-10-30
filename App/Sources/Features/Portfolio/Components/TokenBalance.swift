import Foundation
import Portfolio
import SwiftUI

/// Shows an exact token quantity.
struct TokenBalance: View {
    let amount: Amount
    var symbol: String?
    /// Whether balances from 10,000 up are shortened.
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
        .contentTransition(.numericText(value: Double(amount.units) / pow(10, Double(amount.decimals))))
    }
}

#Preview {
    TokenBalance(amount: Amount(units: 12_500_000_000, decimals: 9), symbol: "SOL")
}
