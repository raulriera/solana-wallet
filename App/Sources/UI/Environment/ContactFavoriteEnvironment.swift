import SwiftUI

extension EnvironmentValues {
    /// Adds an account or contact to Favorites or removes it; `nil` outside Contacts, where nothing is listed.
    @Entry var contactFavorite: ContactFavoriteAction?
}
