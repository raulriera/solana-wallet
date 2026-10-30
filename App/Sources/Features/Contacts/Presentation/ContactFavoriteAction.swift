import SwiftUI

/// An action that adds an account or contact to Favorites or removes it.
struct ContactFavoriteAction {
    let contacts: ContactsModel
    let lists: ContactLists
    let store: ContactStore

    /// Adds an account or contact to Favorites or removes it.
    ///
    /// - Parameters:
    ///   - isFavorite: Whether the account or contact shows under Favorites.
    ///   - contact: The listed account or contact.
    func callAsFunction(_ isFavorite: Bool, for contact: Contact) {
        contacts.setFavorite(isFavorite, for: contact, in: lists, store: store)
    }
}
