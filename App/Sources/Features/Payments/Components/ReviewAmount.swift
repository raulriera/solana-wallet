import SwiftUI

/// A payment's amount at the top of its review: its worth in large digits over the token quantity, or the quantity
/// alone when the token has no price.
struct ReviewAmount: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel

    var body: some View {
        let token = payment.token
        VStack(spacing: 8) {
            Group {
                if let value = payment.value {
                    Text(value, format: .value(code: payment.currencyCode))
                } else {
                    Text(payment.quantity, format: .quantity(of: token))
                }
            }
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            if payment.value != nil {
                Text(payment.quantity, format: .quantity(of: token))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .foregroundStyle(palette.primaryText)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
