import SwiftUI
import Transactions

/// Deletes a contact the person confirmed, from any view in Contacts, the way SwiftUI's `dismiss` acts for the view
/// that reads it.
struct ContactDeletionAction {
    /// The window's contacts, which delete it and explain a deletion that can't be saved.
    let contacts: ContactsModel
    /// The lists that show the contact.
    let lists: ContactLists
    /// The saved contacts that every window shares.
    let store: ContactStore
    /// The tab's selected address, which the deletion clears when it leaves the address without a row.
    let selection: Binding<Address?>

    /// Deletes a contact; a paid address stays selected under Recents, and any other leaves nothing selected.
    /// - Parameter contact: The contact to delete.
    func callAsFunction(_ contact: Contact) {
        contacts.delete(contact, from: store)
        if selection.wrappedValue == contact.address, !lists.keepsRow(afterDeleting: contact) {
            selection.wrappedValue = nil
        }
    }
}
