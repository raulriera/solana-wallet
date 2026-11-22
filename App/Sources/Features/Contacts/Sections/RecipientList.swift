import SwiftUI
import Transactions

/// Lists the addresses an account can pay, with a row for a new payment's unlisted address.
struct RecipientList: View {
    @Binding var selection: Address?
    /// The contact whose deletion waits for confirmation.
    @State private var removal: Contact?
    let lists: ContactLists

    var body: some View {
        List(selection: $selection) {
            if let newPayment = selection, !lists.lists(newPayment) {
                Section {
                    RecipientRow(name: nil, address: newPayment, date: nil)
                        .tag(newPayment)
                } header: {
                    Text("New Payment")
                        .foregroundStyle(.secondary)
                }
            }

            if !lists.accounts.isEmpty {
                Section {
                    ForEach(lists.accounts) { account in
                        RecipientRow(name: account.name, address: account.address, date: nil)
                            .tag(account.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: account)
                                    .swipeActionTint(.yellow)
                            }
                    }
                } header: {
                    Text("My Accounts")
                        .foregroundStyle(.secondary)
                }
            }

            if !lists.favorites.isEmpty {
                Section {
                    ForEach(lists.favorites) { favorite in
                        RecipientRow(name: favorite.name, address: favorite.address, date: nil)
                            .tag(favorite.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: favorite)
                                    .swipeActionTint(.yellow)
                            }
                    }
                } header: {
                    Text("Favorites")
                        .foregroundStyle(.secondary)
                }
            }

            if !lists.contacts.isEmpty {
                Section {
                    ForEach(lists.contacts) { contact in
                        RecipientRow(name: contact.name, address: contact.address, date: nil)
                            .tag(contact.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: contact)
                                    .swipeActionTint(.yellow)
                            }
                            .swipeDelete(contact, removal: $removal)
                            .contactDeletion(of: contact, removal: $removal)
                    }
                } header: {
                    Text("Contacts")
                        .foregroundStyle(.secondary)
                }
            }

            if !lists.recents.isEmpty {
                Section {
                    ForEach(lists.recents) { payment in
                        RecipientRow(name: nil, address: payment.address, date: payment.date)
                            .tag(payment.address)
                            .swipeActions(edge: .leading) {
                                AddContactButton(address: payment.address)
                                    .swipeActionTint(.blue)
                            }
                    }
                } header: {
                    Text("Recents")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: lists.isLoaded)
    }
}
