import SwiftUI

extension EnvironmentValues {
    /// Deletes a contact the person confirmed; `nil` outside Contacts, where no contact is listed.
    @Entry var contactDeletion: ContactDeletionAction?
}
