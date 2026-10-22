import SwiftUI

/// Shows how much the payment sends and in which token, before the person sends it from the top bar.
struct PaymentReviewScreen: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel

    var body: some View {
        Form {
            Section {
                ReviewAmount(payment: payment)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("Pay With") {
                    Text(payment.token.symbol)
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
