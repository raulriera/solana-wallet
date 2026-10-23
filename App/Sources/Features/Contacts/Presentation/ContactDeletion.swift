import SwiftUI
import Transactions

/// Asks before deleting a contact, from the view where the deletion starts, so the confirmation points at it.
private struct ContactDeletion: ViewModifier {
    /// The contact waiting for the person to confirm its deletion.
    @Binding var removal: Contact?
    let contacts: ContactsModel
    /// The window's selected address, which the deletion clears when it leaves the address without a row.
    @Binding var selection: Address?

    /// Adds the confirmation, which deletes the contact only when the person confirms.
    /// - Parameter content: The view where the deletion starts.
    /// - Returns: The view with the deletion's confirmation.
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Delete Contact?", item: $removal) { contact in
                Button("Delete Contact", role: .destructive) {
                    withAnimation {
                        contacts.delete(contact)
                        // A paid address stays selected under Recents; any other leaves nothing selected.
                        if selection == contact.address, !contacts.lists(contact.address) { selection = nil }
                    }
                }
            } message: { contact in
                Text("\(contact.name) will be removed from your contacts.",
                     comment: "Message when deleting a contact. The variable is the contact's name.")
            }
    }
}

extension View {
    /// Asks before deleting a contact, from this view.
    /// - Parameters:
    ///   - removal: The contact waiting for the person to confirm its deletion.
    ///   - contacts: The window's contacts, which delete it.
    ///   - selection: The window's selected address, which the deletion clears when it leaves the address without a
    ///     row.
    /// - Returns: The view with the deletion's confirmation.
    func contactDeletion(_ removal: Binding<Contact?>, from contacts: ContactsModel,
                         selection: Binding<Address?>) -> some View {
        modifier(ContactDeletion(removal: removal, contacts: contacts, selection: selection))
    }
}
