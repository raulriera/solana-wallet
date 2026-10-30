import SwiftUI

extension EnvironmentValues {
    /// The action that adds or removes a favorite, or `nil` outside Contacts.
    @Entry var contactFavorite: ContactFavoriteAction?
}
