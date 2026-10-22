import SwiftUI
import Transactions

/// Lists the addresses a window can pay as native sidebar rows: the wallet's other accounts, favorites, contacts,
/// and recent payments to unsaved addresses.
struct RecipientList: View {
    /// The selected address; every row that lists it is highlighted.
    @Binding var selection: Address?
    /// The window's recipient sheet, which saves a recent address as a contact.
    @Binding var entry: RecipientEntryModel?
    /// The contact waiting for the person to confirm its deletion.
    @Binding var removal: Contact?
    let contacts: ContactsModel

    var body: some View {
        List(selection: $selection) {
            if !contacts.accounts.isEmpty {
                Section("My Accounts") {
                    ForEach(contacts.accounts) { account in
                        RecipientRow(name: account.name, address: account.address, date: nil,
                                     systemImage: "wallet.bifold")
                            .tag(account.address)
                            .swipeActions(edge: .leading) {
                                FavoriteButton(contact: account, contacts: contacts)
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
                                FavoriteButton(contact: favorite, contacts: contacts)
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
                                FavoriteButton(contact: contact, contacts: contacts)
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
                                AddContactButton(address: payment.address, contacts: contacts, entry: $entry)
                                    .swipeActionTint(.blue)
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
