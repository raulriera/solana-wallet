import SwiftUI

extension EnvironmentValues {
    /// The action that deletes a contact, or `nil` outside Contacts.
    @Entry var contactDeletion: ContactDeletionAction?
}
