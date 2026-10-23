import SwiftUI
import Transactions

/// Lists the addresses a window can pay as native sidebar rows: the wallet's other accounts, favorites, contacts, and
/// recent payments to unsaved addresses. A new payment's address that none of them lists gets its own row while it's
/// selected, like Messages' New Message row, so every selection has a row.
struct RecipientList: View {
    /// The selected address; every row that lists it is highlighted.
    @Binding var selection: Address?
    /// The contact waiting for the person to confirm its deletion.
    @State private var removal: Contact?
    let contacts: ContactsModel

    var body: some View {
        @Bindable var contacts = contacts
        List(selection: $selection) {
            if let newPayment = selection, !contacts.lists(newPayment) {
                Section("New Payment") {
                    RecipientRow(name: nil, address: newPayment, date: nil, systemImage: "square.and.pencil")
                        .tag(newPayment)
                }
            }

            if !contacts.accounts.isEmpty {
                Section("My Accounts") {
                    ForEach(contacts.accounts) { account in
                        RecipientRow(name: account.name, address: account.address, date: nil,
                                     systemImage: "wallet.bifold")
                            .tag(account.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(isFavorite: $contacts[isFavorite: account])
                                    .swipeActionTint(.yellow)
                            }
                    }
                }
            }

            if !contacts.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(contacts.favorites) { favorite in
                        RecipientRow(name: favorite.name, address: favorite.address, date: nil, systemImage: "star")
                            .tag(favorite.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(isFavorite: $contacts[isFavorite: favorite])
                                    .swipeActionTint(.yellow)
                            }
                    }
                }
            }

            if !contacts.contacts.isEmpty {
                Section("Contacts") {
                    ForEach(contacts.contacts) { contact in
                        RecipientRow(name: contact.name, address: contact.address, date: nil,
                                     systemImage: "person.crop.circle")
                            .tag(contact.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(isFavorite: $contacts[isFavorite: contact])
                                    .swipeActionTint(.yellow)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                SwipeDeleteButton(removal: $removal, item: contact)
                            }
                    }
                }
            }

            if !contacts.recents.isEmpty {
                Section("Recents") {
                    ForEach(contacts.recents) { payment in
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
        .contactDeletion($removal, from: contacts, selection: $selection)
    }
}
