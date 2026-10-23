import SwiftUI
import Transactions

/// Opens the window's recipient sheet to save an address as a contact or to edit a contact, from any view in
/// Contacts, the way SwiftUI's `dismiss` acts for the view that reads it.
struct ContactEntryAction {
    /// The window's contacts, which the sheet checks the address against and saves to.
    let contacts: ContactsModel
    /// The window's recipient sheet.
    let entry: Binding<RecipientEntryModel?>

    /// Opens the sheet that saves an address as a contact.
    /// - Parameter address: The address to save.
    func callAsFunction(savingContactAt address: Address) {
        entry.wrappedValue = RecipientEntryModel(savingContactAt: address, contacts: contacts)
    }

    /// Opens the sheet that edits a contact's name and address.
    /// - Parameter contact: The contact to edit.
    func callAsFunction(editing contact: Contact) {
        entry.wrappedValue = RecipientEntryModel(editing: contact, contacts: contacts)
    }
}

extension EnvironmentValues {
    /// Opens the window's recipient sheet; `nil` outside Contacts, where no sheet can open.
    @Entry var contactEntry: ContactEntryAction?
}
