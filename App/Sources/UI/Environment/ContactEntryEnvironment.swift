import SwiftUI

extension EnvironmentValues {
    /// Opens the window's recipient sheet; `nil` outside Contacts, where no sheet can open.
    @Entry var contactEntry: ContactEntryAction?
}
