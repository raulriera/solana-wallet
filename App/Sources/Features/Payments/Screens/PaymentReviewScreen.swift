import SwiftUI
import Transactions

/// Shows how much the payment sends, in which token, and to whom, with anything to check about the recipient,
/// before the person sends it from the top bar.
struct PaymentReviewScreen: View {
    @Environment(\.palette) private var palette
    let payment: PaymentModel
    let recipient: PaymentRecipient
    /// What to check about the recipient, most serious first.
    let warnings: [RecipientWarning]

    var body: some View {
        Form {
            Section {
                ReviewAmount(payment: payment)
            }
            .listRowBackground(Color.clear)

            Section {
                if let name = recipient.name {
                    Text(name)
                }
                // The whole address, so people can check every character before sending.
                FullAddress(text: recipient.address.value)
                ForEach(warnings, id: \.self) { warning in
                    RecipientWarningLabel(warning: warning)
                }
            } header: {
                Text("To")
            }
            .listRowBackground(palette.surface)

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
