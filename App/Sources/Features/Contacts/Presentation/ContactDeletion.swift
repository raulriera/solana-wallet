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
            .confirmation("Delete Contact?", action: "Delete Contact", isPresented: $removal[isPresenting: contact],
                          perform: delete) {
                Text("\(contact.name) will be removed from your contacts.",
                     comment: "Message when deleting a contact. The variable is the contact's name.")
            }
    }

    /// Deletes the contact with animation.
    private func delete() {
        withAnimation { contactDeletion?(contact) }
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

nonisolated private extension Optional where Wrapped: Equatable {
    /// Accesses whether a specific value is present; setting it to `false` clears that value.
    ///
    /// - Parameter value: The value to look for.
    /// - Returns: `true` when the optional holds `value`.
    subscript(isPresenting value: Wrapped) -> Bool {
        get { self == value }
        set { if !newValue, self == value { self = nil } }
    }
}
