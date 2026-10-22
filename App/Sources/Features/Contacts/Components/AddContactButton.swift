import SwiftUI
import Transactions

/// Opens the sheet that saves an address as a contact under a name.
struct AddContactButton: View {
    let address: Address
    let contacts: ContactsModel
    /// The window's recipient sheet.
    @Binding var entry: RecipientEntryModel?

    var body: some View {
        Button("Add Contact", systemImage: "person.crop.circle.badge.plus") {
            entry = RecipientEntryModel(savingContactAt: address, contacts: contacts)
        }
    }
}
