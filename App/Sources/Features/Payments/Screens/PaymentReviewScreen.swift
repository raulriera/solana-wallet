import SwiftUI

/// Shows how much the payment sends and in which token, before the person sends it from the top bar.
struct PaymentReviewScreen: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel

    var body: some View {
        let token = payment.token
        Form {
            Section {
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
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("Pay With") {
                    Text(token.symbol)
                }
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
