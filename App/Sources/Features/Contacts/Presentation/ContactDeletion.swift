import SwiftUI
import Transactions

/// Asks before deleting a contact, from the view where the deletion starts, so the confirmation points at it.
private struct ContactDeletion: ViewModifier {
    /// The contact waiting for the person to confirm its deletion.
    @Binding var removal: Contact?
    /// The contact this view deletes; the confirmation shows only while it's the one waiting.
    let contact: Contact
    let contacts: ContactsModel
    /// The window's selected address, which the deletion clears when it leaves the address without a row.
    @Binding var selection: Address?

    /// Adds the confirmation, which deletes the contact only when the person confirms.
    /// - Parameter content: The view where the deletion starts.
    /// - Returns: The view with the deletion's confirmation.
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Delete Contact?", isPresented: $removal[isRemoving: contact],
                                presenting: contact) { contact in
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

private extension Optional where Wrapped == Contact {
    /// Whether a contact is the one waiting for confirmation; dismissing its confirmation stops the wait.
    /// - Parameter contact: The contact a view deletes.
    subscript(isRemoving contact: Contact) -> Bool {
        get { self?.id == contact.id }
        set { if !newValue, self?.id == contact.id { self = nil } }
    }
}

extension View {
    /// Asks before deleting a contact, from this view, such as the contact's row or Delete button.
    /// - Parameters:
    ///   - contact: The contact this view deletes.
    ///   - removal: The contact waiting for the person to confirm its deletion; the confirmation shows here only while
    ///     it's `contact`.
    ///   - contacts: The window's contacts, which delete it.
    ///   - selection: The window's selected address, which the deletion clears when it leaves the address without a
    ///     row.
    /// - Returns: The view with the deletion's confirmation.
    func contactDeletion(of contact: Contact, removal: Binding<Contact?>, from contacts: ContactsModel,
                         selection: Binding<Address?>) -> some View {
        modifier(ContactDeletion(removal: removal, contact: contact, contacts: contacts, selection: selection))
    }
}
