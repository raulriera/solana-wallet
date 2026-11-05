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
                Section("New Payment") {
                    RecipientRow(name: nil, address: newPayment, date: nil, systemImage: "square.and.pencil")
                        .tag(newPayment)
                }
            }

            if !lists.accounts.isEmpty {
                Section("My Accounts") {
                    ForEach(lists.accounts) { account in
                        RecipientRow(name: account.name, address: account.address, date: nil,
                                     systemImage: "wallet.bifold")
                            .tag(account.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: account)
                                    .swipeActionTint(.yellow)
                            }
                    }
                }
            }

            if !lists.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(lists.favorites) { favorite in
                        RecipientRow(name: favorite.name, address: favorite.address, date: nil, systemImage: "star")
                            .tag(favorite.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: favorite)
                                    .swipeActionTint(.yellow)
                            }
                    }
                }
            }

            if !lists.contacts.isEmpty {
                Section("Contacts") {
                    ForEach(lists.contacts) { contact in
                        RecipientRow(name: contact.name, address: contact.address, date: nil,
                                     systemImage: "person.crop.circle")
                            .tag(contact.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: contact)
                                    .swipeActionTint(.yellow)
                            }
                            .swipeDelete(contact, removal: $removal)
                            .contactDeletion(of: contact, removal: $removal)
                    }
                }
            }

            if !lists.recents.isEmpty {
                Section("Recents") {
                    ForEach(lists.recents) { payment in
                        RecipientRow(name: nil, address: payment.address, date: payment.date, systemImage: "clock")
                            .tag(payment.address)
                            .swipeActions(edge: .leading) {
                                AddContactButton(address: payment.address)
                                    .swipeActionTint(.blue)
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
