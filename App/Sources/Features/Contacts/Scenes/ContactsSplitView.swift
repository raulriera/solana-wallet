import RPC
import SwiftUI
import Transactions

/// Shows the addresses an account can pay in a sidebar and the keypad for the selected one.
struct ContactsSplitView: View {
    @Environment(ContactStore.self) private var store
    @Environment(AccountStore.self) private var accounts
    @Environment(TransactionStore.self) private var transactions
    /// The account that pays.
    let account: Account
    let network: Network
    @Bindable var contacts: ContactsModel
    /// The number of Try Again taps.
    @State private var loadAttempt = 0
    @State private var selection: Address?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var payment = KeypadPayment.loading
    /// The review of the last sent payment.
    @State private var review: TransactionReviewModel<PaymentProposal>?
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    @State private var entry: RecipientEntryModel?

    var body: some View {
        let lists = contacts.lists(for: account, on: network, in: accounts.accounts(inWallet: account.recoveryID),
                                   store: store, transactions: transactions)
        let isEmpty = lists.isEmpty && selection == nil
        ZStack {
            if lists.isUnreadable {
                UnavailableScreen(title: "Contacts Unavailable",
                                  message: "Your saved contacts couldn't be loaded. Try again.",
                                  systemImage: "exclamationmark.triangle") {
                    Button("Try Again") { loadAttempt += 1 }
                        .buttonStyle(.primary)
                }
            } else if !lists.isLoaded {
                Color.clear
            } else if isEmpty {
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
                            .id(selection)
                    } else if selection != nil {
                        Color.clear
                    } else {
                        UnavailableScreen(title: "No Recipient Selected",
                                          message: "Choose who to pay, or paste an address for a new payment.",
                                          systemImage: "person.crop.circle") {}
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewStyle(.tabSection)
            }
        }
        .animation(.default, value: isEmpty)
        .keypadPayment(for: account, on: network, into: $payment)
        .clearsSentAmount(payment.model, review: $review)
        .task(id: Load(attempt: loadAttempt, keys: lists.keys)) {
            await contacts.load(lists.keys, from: store, transactions: transactions)
        }
        .errorAlert($contacts.error)
        .environment(\.contactEntry, ContactEntryAction(lists: lists, entry: $entry))
        .environment(\.contactFavorite, ContactFavoriteAction(contacts: contacts, lists: lists, store: store))
        .environment(\.contactDeletion,
                     ContactDeletionAction(contacts: contacts, lists: lists, store: store, selection: $selection))
        .sheet(item: $entry) { RecipientEntrySheet(entry: $0, lists: lists) }
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard let confirmation else { return }
            if let contact = confirmation.contact { contacts.save(contact, in: store) }
            switch confirmation.purpose {
            case .payment:
                withAnimation { selection = confirmation.address }
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

    /// The identity of a read of the saved contacts and records.
    private struct Load: Hashable {
        let attempt: Int
        let keys: [TransactionRecord.Key]
    }
}
