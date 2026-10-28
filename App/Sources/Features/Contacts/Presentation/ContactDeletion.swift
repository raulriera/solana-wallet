import SwiftUI

/// Asks before deleting a contact, from the view where the deletion starts, so the confirmation points at it.
private struct ContactDeletion: ViewModifier {
    @Environment(\.contactDeletion) private var contactDeletion
    /// The contact waiting for the person to confirm its deletion.
    @Binding var removal: Contact?
    /// The contact this view deletes; the confirmation shows only while it's the one waiting.
    let contact: Contact

    /// Adds the confirmation, which deletes the contact only when the person confirms.
    /// - Parameter content: The view where the deletion starts.
    /// - Returns: The view with the deletion's confirmation.
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Delete Contact?", isPresented: $removal[isRemoving: contact],
                                presenting: contact) { contact in
                Button("Delete Contact", role: .destructive) {
                    withAnimation { contactDeletion?(contact) }
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
    /// - Returns: The view with the deletion's confirmation.
    func contactDeletion(of contact: Contact, removal: Binding<Contact?>) -> some View {
        modifier(ContactDeletion(removal: removal, contact: contact))
    }
}
