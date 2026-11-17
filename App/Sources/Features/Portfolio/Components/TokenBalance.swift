import Foundation
import SwiftUI
import Transactions

/// Shows a token quantity: exactly with the asset's symbol, or alone and, when asked, shortened from 10,000 up.
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
        .contentTransition(.numericText(value: Decimal(balance)))
    }
}

#Preview {
    TokenBalance(balance: TokenAmount(lamports: 12_500_000_000), asset: .nativeSOL)
}
