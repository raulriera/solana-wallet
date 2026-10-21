#if DEBUG
import SwiftUI
import Transactions

/// Owns the contacts tab: the addresses the window's account can pay in the sidebar, and the keypad as the detail
/// of the selected one.
///
/// Contacts and recent payments start empty until they're stored; the keypad still uses sample tokens.
struct ContactsScene: View {
    @State private var contacts: ContactsModel
    /// The selected address; every row that lists it is highlighted, so it stays highlighted when it moves to
    /// another section, such as a favorite that's removed.
    @State private var selection: Address?
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    /// The payment being typed; it stays when the person picks another recipient.
    @State private var payment = PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD")
    @State private var isReviewing = false
    /// Matches the Send button with the review, which grows out of it.
    @Namespace private var review
    /// The contact waiting for the person to confirm its deletion.
    @State private var removal: Contact?

    /// Lists the addresses an account can pay, created once for the scene; the owner gives another account a new
    /// scene.
    /// - Parameter account: The window's account, which payments leave from.
    init(account: Account) {
        contacts = ContactsModel(sendingAccount: account.address)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            Group {
                if contacts.isEmpty {
                    UnavailableScreen(title: "No Contacts",
                                      message: "People you save and pay appear here.",
                                      systemImage: "person.crop.circle") {}
                } else {
                    RecipientList(selection: $selection, removal: $removal, contacts: contacts)
                }
            }
            .navigationTitle("Contacts")
            .sidebarColumnWidth()
        } detail: {
            if selection != nil {
                PaymentAmountScreen(payment: payment, title: "Send") {
                    SendButton(payment: payment, isReviewing: $isReviewing)
                        .matchedTransitionSource(id: ObjectIdentifier(payment), in: review)
                }
            } else {
                UnavailableScreen(title: "No Recipient Selected", message: "Choose who to pay.",
                                  systemImage: "person.crop.circle") {}
                // Inline like the keypad, so a cleared selection leaves no empty large title.
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationSplitViewStyle(.tabSection)
        .sheet(isPresented: $isReviewing) {
            PaymentReviewSheet(payment: payment)
                // The review grows out of the Send button, and shrinks back into it when canceled.
                .navigationTransition(.zoom(sourceID: ObjectIdentifier(payment), in: review))
        }
        .confirmationDialog("Delete Contact?", item: $removal) { contact in
            Button("Delete Contact", role: .destructive) {
                withAnimation { contacts.delete(contact) }
            }
        } message: { contact in
            Text("\(contact.name) will be removed from your contacts.",
                 comment: "Message when deleting a contact. The variable is the contact's name.")
        }
    }
}
#endif
