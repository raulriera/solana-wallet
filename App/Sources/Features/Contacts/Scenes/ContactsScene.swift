#if DEBUG
import SwiftUI
import Transactions

/// Owns the contacts tab: the addresses the window's account can pay in the sidebar, the keypad as the detail of the
/// selected one, and the sheet that enters a new recipient.
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
    /// The sheet that enters a new payment's recipient or saves a recent address as a contact.
    @State private var entry: RecipientEntryModel?
    /// The contact waiting for the person to confirm its deletion.
    @State private var removal: Contact?

    /// Lists the addresses an account can pay, created once for the scene; the owner gives another account a new
    /// scene.
    /// - Parameter account: The window's account, which payments leave from.
    init(account: Account) {
        contacts = ContactsModel(sendingAccount: account.address)
    }

    var body: some View {
        let isEmpty = contacts.isEmpty && selection == nil
        // One container, so the presentations and changes below attach once instead of to each branch.
        ZStack {
            if isEmpty {
                // With no one to list or pay, one screen spans the tab instead of an empty state in each column.
                UnavailableScreen(title: "No Contacts",
                                  message: "Paste an address to make your first payment. Name it to save it as a contact.",
                                  systemImage: "person.crop.circle") {
                    Button("New Payment", action: startPayment)
                        .buttonStyle(.primary)
                }
            } else {
                NavigationSplitView(preferredCompactColumn: $preferredColumn) {
                    Group {
                        if contacts.isEmpty {
                            // The keypad beside it already pays someone, and New Payment is in the top bar.
                            UnavailableScreen(title: "No Contacts",
                                              message: "People you name or pay appear here.",
                                              systemImage: "person.crop.circle") {}
                        } else {
                            RecipientList(selection: $selection, entry: $entry, removal: $removal, contacts: contacts)
                        }
                    }
                    .navigationTitle("Contacts")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                            Button("New Payment", systemImage: "plus", action: startPayment)
                                .tint(.primary)
                        }
                    }
                    .sidebarColumnWidth()
                } detail: {
                    if let selection {
                        PaymentAmountScreen(payment: payment, recipient: contacts.recipient(for: selection)) {
                            SendButton(payment: payment, isReviewing: $isReviewing)
                                .matchedTransitionSource(id: ObjectIdentifier(payment), in: review)
                        }
                    } else {
                        UnavailableScreen(title: "No Recipient Selected",
                                          message: "Choose who to pay, or paste an address for a new payment.",
                                          systemImage: "person.crop.circle") {
                            Button("New Payment", action: startPayment)
                                .buttonStyle(.primary)
                        }
                        // Inline like the keypad, so a cleared selection leaves no empty large title.
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewStyle(.tabSection)
            }
        }
        .animation(.default, value: isEmpty)
        .sheet(isPresented: $isReviewing) {
            if let selection {
                PaymentReviewSheet(payment: payment, recipient: contacts.recipient(for: selection),
                                   context: contacts.recipientContext)
                    // The review grows out of the Send button, and shrinks back into it when canceled.
                    .navigationTransition(.zoom(sourceID: ObjectIdentifier(payment), in: review))
            }
        }
        .sheet(item: $entry) { RecipientEntrySheet(entry: $0) }
        // A new payment's recipient opens the keypad; a saved contact keeps whatever is selected.
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard let confirmation, confirmation.purpose == .payment else { return }
            selection = confirmation.address
            preferredColumn = .detail
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

    /// Opens the sheet that enters a new payment's recipient.
    private func startPayment() {
        entry = RecipientEntryModel(contacts: contacts)
    }
}
#endif
