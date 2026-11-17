import Foundation
import SwiftUI
import Transactions

/// Shows an exact token quantity.
struct TokenBalance: View {
    let balance: TokenAmount
    /// The asset whose symbol follows the quantity, or `nil` for the quantity alone.
    var asset: Asset?
    /// Whether balances from 10,000 up are shortened.
    var abbreviates = false

    var body: some View {
        Group {
            if let asset {
                Text(balance, format: .amount(of: asset))
            } else {
                Text(balance, format: abbreviates ? .abbreviatedAmount : .amount)
                    .accessibilityLabel(Text(balance, format: .amount))
            }
        }
        .contentTransition(.numericText(value: Double(balance.amount) / pow(10, Double(balance.decimals))))
    }
}

#Preview {
    TokenBalance(balance: TokenAmount(lamports: 12_500_000_000), asset: .nativeSOL)
}
