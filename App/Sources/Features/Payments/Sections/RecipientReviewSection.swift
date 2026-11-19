import SwiftUI
import Transactions

/// Shows the recipient of a review: their name in the header, their full address, and the warnings about them.
struct RecipientReviewSection: View {
    let recipient: PaymentRecipient
    /// The recipient warnings, most serious first.
    let warnings: [RecipientWarning]

    var body: some View {
        Section {
            FullAddress(text: recipient.address.value)
            ForEach(warnings, id: \.self) { warning in
                RecipientWarningLabel(warning: warning)
            }
        } header: {
            if let name = recipient.name {
                Text("To \(name)",
                     comment: "Header above the address a payment goes to. The variable is the recipient's name.")
            } else {
                Text("To")
            }
        }
    }
}
