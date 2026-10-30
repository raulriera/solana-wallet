import SwiftUI

/// A modifier that asks the person to confirm a contact's deletion before deleting it.
private struct ContactDeletion: ViewModifier {
    @Environment(\.contactDeletion) private var contactDeletion
    /// The contact whose deletion waits for confirmation.
    @Binding var removal: Contact?
    /// The contact that this view deletes.
    let contact: Contact

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
    /// Accesses whether a contact's deletion waits for confirmation, and stops the wait when set to `false`.
    ///
    /// - Parameter contact: The contact that a view deletes.
    /// - Returns: `true` when the contact's deletion waits for confirmation.
    subscript(isRemoving contact: Contact) -> Bool {
        get { self?.id == contact.id }
        set { if !newValue, self?.id == contact.id { self = nil } }
    }
}

extension View {
    /// Asks the person to confirm a contact's deletion before deleting it.
    ///
    /// - Parameters:
    ///   - contact: The contact that this view deletes.
    ///   - removal: The contact whose deletion waits for confirmation.
    /// - Returns: The view with the deletion's confirmation.
    func contactDeletion(of contact: Contact, removal: Binding<Contact?>) -> some View {
        modifier(ContactDeletion(removal: removal, contact: contact))
    }
}
