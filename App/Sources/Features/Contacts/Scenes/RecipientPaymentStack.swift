import SwiftUI
import Transactions

/// Pays one recipient on the keypad in its own navigation container, with their details a push away and the
/// payment's review growing out of the Send button.
struct RecipientPaymentStack: View {
    let recipient: PaymentRecipient
    /// The payment being typed; it stays when the person picks another recipient.
    let payment: PaymentModel
    let contacts: ContactsModel
    /// The window's selected address, which deleting the recipient's contact from their details clears.
    @Binding var selection: Address?
    /// The window's recipient sheet, which the details open to save or edit the contact.
    @Binding var entry: RecipientEntryModel?
    @State private var isReviewing = false
    @State private var showsDetails = false
    /// Matches the Send button with the review, which grows out of it.
    @Namespace private var review

    var body: some View {
        NavigationStack {
            PaymentAmountScreen(payment: payment, recipient: recipient) {
                SendButton(payment: payment, isReviewing: $isReviewing)
                    .matchedTransitionSource(id: ObjectIdentifier(payment), in: review)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                    Button("Details", systemImage: "info.circle") { showsDetails = true }
                        .tint(.primary)
                }
            }
            .navigationDestination(isPresented: $showsDetails) {
                RecipientScreen(address: recipient.address, contacts: contacts, selection: $selection, entry: $entry)
            }
        }
        .sheet(isPresented: $isReviewing) {
            PaymentReviewSheet(payment: payment, recipient: recipient, context: contacts.recipientContext)
                // The review grows out of the Send button, and shrinks back into it when canceled.
                .navigationTransition(.zoom(sourceID: ObjectIdentifier(payment), in: review))
        }
    }
}
