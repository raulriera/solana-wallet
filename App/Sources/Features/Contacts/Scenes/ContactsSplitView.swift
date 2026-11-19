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
    let contacts: ContactsModel
    @State private var selection: Address?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var payment = KeypadPayment.loading
    /// The review of the last sent payment.
    @State private var review: TransactionReviewModel<PaymentProposal>?
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    @State private var entry: RecipientEntryModel?

    var body: some View {
        let lists = contacts.lists(for: account, on: network, in: accounts.accounts,
                                   store: store, transactions: transactions)
        ContactsContainer(selection: $selection, lists: lists, contacts: contacts, entry: $entry) {
            NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
                RecipientList(selection: $selection, lists: lists)
                .navigationTitle("Contacts")
                .sidebarColumn()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Payment", systemImage: "plus") { entry = RecipientEntryModel() }
                            .tint(.primary)
                    }
                }
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
                    .toolbarTitleDisplayMode(.inline)
                }
            }
            .navigationSplitViewStyle(.tabSection)
        }
        .keypadPayment(for: account, on: network, into: $payment)
        .clearsSentAmount(payment.model, review: $review)
        .environment(\.newPayment, NewPaymentAction(selection: $selection))
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard confirmation?.purpose == .payment else { return }
            columnVisibility = .detailOnly
            preferredColumn = .detail
        }
    }
}
