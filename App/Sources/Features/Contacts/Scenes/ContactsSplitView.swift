import RPC
import SwiftUI
import Transactions

/// Shows the contacts tab's split view: the addresses an account can pay in the sidebar, the keypad as the detail of
/// the selected one, and the sheet that enters a new recipient.
///
/// The keypad pays with the account's tokens that have a balance, on the network.
struct ContactsSplitView: View {
    @Environment(ContactStore.self) private var store
    @Environment(AccountStore.self) private var accounts
    @Environment(TransactionStore.self) private var transactions
    /// The account payments leave from.
    let account: Account
    /// The network whose recent payments are listed and whose tokens pay.
    let network: Network
    /// The tab's changes to contacts and favorites, which ``ContactsScene`` owns.
    @Bindable var contacts: ContactsModel
    /// Counts Try Again taps after the saved contacts couldn't be read.
    @State private var loadAttempt = 0
    /// The selected address; every row that lists it is highlighted, so it stays highlighted when it moves to
    /// another section, such as a favorite that's removed.
    @State private var selection: Address?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    /// What the keypad pays with; the payment being typed stays when the person picks another recipient.
    @State private var payment = KeypadPayment.loading
    /// The latest payment's review; the owner of the amount keeps it, so the amount clears once that payment succeeds,
    /// even after the person picked another recipient or went back to the list.
    @State private var review: TransactionReviewModel<PaymentProposal>?
    /// The sheet that enters a new payment's recipient or saves a recent address as a contact.
    @State private var entry: RecipientEntryModel?

    var body: some View {
        let lists = contacts.lists(for: account, on: network, in: accounts.accounts(inWallet: account.recoveryID),
                                   store: store, transactions: transactions)
        let isEmpty = lists.isEmpty && selection == nil
        // One container, so the presentations and changes below attach once instead of to each branch.
        ZStack {
            if lists.isUnreadable {
                // Nothing saved is replaced, so the person can try again without losing contacts.
                UnavailableScreen(title: "Contacts Unavailable",
                                  message: "Your saved contacts couldn't be loaded. Try again.",
                                  systemImage: "exclamationmark.triangle") {
                    Button("Try Again") { loadAttempt += 1 }
                        .buttonStyle(.primary)
                }
            } else if !lists.isLoaded {
                // A local read is quick, so nothing shows until it finishes instead of a flashing empty state.
                Color.clear
            } else if isEmpty {
                // With no one to list or pay, one screen spans the tab instead of an empty state in each column.
                UnavailableScreen(title: "No Contacts",
                                  message: "Paste an address to make your first payment. Name it to save it as a contact.",
                                  systemImage: "person.crop.circle") {
                    Button("New Payment", action: startPayment)
                        .buttonStyle(.primary)
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
                    RecipientList(selection: $selection, lists: lists)
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
                    if let selection, !payment.isLoading {
                        RecipientPaymentStack(recipient: lists.recipient(for: selection), payment: payment.model,
                                              context: lists.recipientContext,
                                              sender: PaymentSender(account: account, network: network,
                                                                    transactions: transactions),
                                              review: $review) {
                            RecipientScreen(address: selection, lists: lists)
                        }
                        // Another recipient starts on the keypad, not on the previous one's details.
                            .id(selection)
                    } else if selection != nil {
                        // The balances arrive quickly, so nothing shows until then instead of a flashing empty state.
                        Color.clear
                    } else {
                        // The sidebar's New Payment button starts a payment, so this screen has no action of its own.
                        UnavailableScreen(title: "No Recipient Selected",
                                          message: "Choose who to pay, or paste an address for a new payment.",
                                          systemImage: "person.crop.circle") {}
                        // Inline like the keypad, so a cleared selection leaves no empty large title.
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewStyle(.tabSection)
            }
        }
        .animation(.default, value: isEmpty)
        .keypadPayment(for: account, on: network, into: $payment)
        .clearsSentAmount(payment.model, review: $review)
        // Reads what's saved when the tab first appears, after Try Again, and for a new account in the wallet; every
        // window shares what's read.
        .task(id: Load(attempt: loadAttempt, keys: lists.keys)) {
            await contacts.load(lists.keys, from: store, transactions: transactions)
        }
        .errorAlert($contacts.error)
        // Rows and details open the sheet to save or edit a contact, change favorites, and delete contacts without
        // holding them.
        .environment(\.contactEntry, ContactEntryAction(lists: lists, entry: $entry))
        .environment(\.contactFavorite, ContactFavoriteAction(contacts: contacts, lists: lists, store: store))
        .environment(\.contactDeletion,
                     ContactDeletionAction(contacts: contacts, lists: lists, store: store, selection: $selection))
        .sheet(item: $entry) { RecipientEntrySheet(entry: $0, lists: lists) }
        // The sheet's contact is saved, a new payment's recipient opens the keypad, and an edited address keeps paying
        // the same contact; a new contact keeps whatever is selected.
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard let confirmation else { return }
            if let contact = confirmation.contact { contacts.save(contact, in: store) }
            switch confirmation.purpose {
            case .payment:
                // An address that no row lists gets a New Payment row, which animates in.
                withAnimation { selection = confirmation.address }
                // A selection made in code doesn't close a sidebar that covers the keypad, so the keypad shows alone;
                // in wide windows this also hides the sidebar beside it until the person shows it again.
                columnVisibility = .detailOnly
                preferredColumn = .detail
            case .addContact:
                break
            case .edit(let contact):
                if selection == contact.address { selection = confirmation.address }
            }
        }
    }

    /// Opens the sheet that enters a new payment's recipient.
    private func startPayment() {
        entry = RecipientEntryModel()
    }

    /// What a read of the saved contacts and records is for: a Try Again tap and the records it reads.
    private struct Load: Hashable {
        let attempt: Int
        let keys: [TransactionRecord.Key]
    }
}
