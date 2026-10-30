import SwiftUI
import Transactions

/// An action that opens the recipient sheet to save an address as a contact or to edit a contact.
struct ContactEntryAction {
    let lists: ContactLists
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    let entry: Binding<RecipientEntryModel?>

    /// Opens the sheet that saves an address as a contact.
    ///
    /// - Parameter address: The address to save.
    func callAsFunction(savingContactAt address: Address) {
        entry.wrappedValue = RecipientEntryModel(savingContactAt: address, in: lists)
    }

    /// Opens the sheet that edits a contact's name and address.
    ///
    /// - Parameter contact: The contact to edit.
    func callAsFunction(editing contact: Contact) {
        entry.wrappedValue = RecipientEntryModel(editing: contact, in: lists)
    }
}
