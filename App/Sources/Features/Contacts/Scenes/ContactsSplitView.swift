import RPC
import SwiftUI
import Transactions

/// Shows the addresses an account can pay in a sidebar and the keypad for the selected one.
struct ContactsSplitView: View {
    @Environment(ContactStore.self) private var store
    @Environment(AccountStore.self) private var accounts
    @Environment(TransactionStore.self) private var transactions
    @Environment(RecentPaymentStore.self) private var recents
    /// The account that pays.
    let account: Account
    let network: Network
    let contacts: ContactsModel
    @State private var selection: Address?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// The split view's width, which the detail column matches when the sidebar is hidden or covers it.
    @State private var splitViewWidth = CGFloat.zero
    @State private var detailWidth = CGFloat.zero
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var payment = KeypadPayment.loading
    /// The review of the last sent payment.
    @State private var review: TransactionReviewModel<PaymentProposal>?
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    @State private var entry: RecipientEntryModel?

    var body: some View {
        let lists = contacts.lists(for: account, on: network, in: accounts.accounts,
                                   store: store, recents: recents)
        ContactsContainer(selection: $selection, lists: lists, contacts: contacts, entry: $entry) {
            NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
                RecipientList(selection: $selection, lists: lists)
                .navigationTitle("Contacts")
                .toolbarTitleDisplayMode(.inline)
                .sidebarColumn()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NewPaymentButton(entry: $entry)
                    }
                }
            } detail: {
                Group {
                    if let selection, !payment.isLoading {
                        RecipientPaymentStack(recipient: lists.recipient(for: selection), payment: payment.model,
                                              context: lists.recipientContext,
                                              sender: PaymentSender(account: account, network: network,
                                                                    transactions: transactions, recents: recents),
                                              review: $review) {
                            RecipientScreen(address: selection, lists: lists)
                        }
                            .id(selection)
                    } else if selection != nil {
                        Color.clear
                    } else {
                        UnavailableScreen(title: "No Recipient Selected",
                                          message: "Choose who to pay, or paste an address for a new payment.",
                                          systemImage: nil) {}
                        .toolbarTitleDisplayMode(.inline)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            }
            .navigationSplitViewStyle(.tabSection)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitViewWidth = $0 }
        }
        .keypadPayment(for: account, on: network, into: $payment)
        .clearsSentAmount(payment.model, review: $review)
        .environment(\.newPayment, NewPaymentAction(selection: $selection))
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard confirmation?.purpose == .payment else { return }
            if detailWidth >= splitViewWidth {
                columnVisibility = .detailOnly
            }
            preferredColumn = .detail
        }
    }
}
