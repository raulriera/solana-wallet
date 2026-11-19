import Portfolio
import RPC
import SwiftUI
import Transactions

/// Presents the choice of who to send a private balance to, and pushes the keypad of the send.
struct PrivateSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactStore.self) private var store
    @Environment(AccountStore.self) private var accounts
    @Environment(RecentPaymentStore.self) private var recents
    @Environment(PrivateBalanceStore.self) private var privateBalances
    /// The account's public holding of the asset that's sent.
    let holding: Holding
    /// The account that sends.
    let account: Account
    let network: Network
    @State private var contacts = ContactsModel()
    /// The chosen recipient's address, or `nil` when none is chosen.
    @State private var selection: Address?
    /// The send to the chosen recipient, or `nil` when none is chosen.
    @State private var move: BalanceMove?
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    @State private var entry: RecipientEntryModel?

    var body: some View {
        let lists = contacts.lists(for: account, on: network, in: accounts.accounts,
                                   store: store, recents: recents)
        NavigationStack {
            ContactsContainer(selection: $selection, lists: lists, contacts: contacts, entry: $entry) {
                RecipientList(selection: $selection, lists: lists)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NewPaymentButton(entry: $entry)
                        }
                    }
            }
            .navigationTitle("Send Privately")
            .toolbarTitleDisplayMode(.inline)
            .cancellationAction()
            .navigationDestination(isPresented: $move.isPresented) {
                if let move { BalanceMoveScreen(move: move) }
            }
            .onChange(of: selection) { _, address in
                move = address.flatMap {
                    privateBalances.move(.send(to: lists.recipient(for: $0), in: lists.recipientContext), of: holding,
                                         for: account, on: network)
                }
            }
            .onChange(of: move?.id) { _, id in
                if id == nil { selection = nil }
            }
        }
        .limitedTextSize()
        .environment(\.dismissParentContainer, dismiss)
    }
}
