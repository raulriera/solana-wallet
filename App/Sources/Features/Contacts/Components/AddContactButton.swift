import SwiftUI
import Transactions

/// A button that opens the sheet that saves an address as a contact.
struct AddContactButton: View {
    @Environment(\.contactEntry) private var contactEntry
    let address: Address

    var body: some View {
        Button("Add Contact", systemImage: "person.crop.circle.badge.plus") {
            contactEntry?(savingContactAt: address)
        }
    }
}
