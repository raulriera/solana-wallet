import SwiftUI

/// A payment's amount at the top of its review: its worth in large digits over the token quantity, or the quantity
/// alone when the token has no price.
struct ReviewAmount: View {
    @Environment(\.palette) private var palette
    let amount: PaymentAmount

    var body: some View {
        let token = amount.token
        VStack(spacing: 8) {
            Group {
                if let value = amount.value {
                    Text(value, format: .value(code: amount.currencyCode))
                } else {
                    Text(amount.quantity, format: .quantity(of: token))
                }
            }
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            if amount.value != nil {
                Text(amount.quantity, format: .quantity(of: token))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .foregroundStyle(palette.primaryText)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
