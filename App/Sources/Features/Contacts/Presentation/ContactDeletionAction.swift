import SwiftUI
import Transactions

/// An action that deletes a contact.
struct ContactDeletionAction {
    let contacts: ContactsModel
    let lists: ContactLists
    let store: ContactStore
    let selection: Binding<Address?>

    /// Deletes a contact and clears the selection when the contact's address leaves the lists.
    ///
    /// - Parameter contact: The contact to delete.
    func callAsFunction(_ contact: Contact) {
        contacts.delete(contact, from: store)
        if selection.wrappedValue == contact.address, !lists.keepsRow(afterDeleting: contact) {
            selection.wrappedValue = nil
        }
    }
}
