import SwiftUI
import Transactions

/// A payment's value in large digits over its token quantity, or the quantity alone when the token has no price.
struct ReviewAmount: View {
    let sent: TokenAmount
    let asset: Asset
    /// What the sent amount is worth, or `nil` when the asset has no price.
    var value: Decimal?
    /// The code of the currency that ``value`` is in, or `nil` without a value.
    var currencyCode: String?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let value, let currencyCode {
                    Text(value, format: .value(code: currencyCode))
                } else {
                    Text(sent, format: .amount(of: asset))
                }
            }
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            if value != nil, currencyCode != nil {
                Text(sent, format: .amount(of: asset))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
