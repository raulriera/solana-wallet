import SwiftUI

extension EnvironmentValues {
    /// The action that opens the recipient sheet, or `nil` outside Contacts.
    @Entry var contactEntry: ContactEntryAction?
}
