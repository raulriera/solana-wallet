import SwiftUI

/// Adds an account or contact to Favorites or removes it, from any view in Contacts, the way SwiftUI's `dismiss` acts
/// for the view that reads it.
struct ContactFavoriteAction {
    /// The window's contacts, which save the change and explain one that can't be saved.
    let contacts: ContactsModel
    /// The lists that show the account or contact.
    let lists: ContactLists
    /// The saved favorites that every window shares.
    let store: ContactStore

    /// Adds an account or contact to Favorites or removes it.
    /// - Parameters:
    ///   - isFavorite: Whether the account or contact shows under Favorites.
    ///   - contact: The listed account or contact.
    func callAsFunction(_ isFavorite: Bool, for contact: Contact) {
        contacts.setFavorite(isFavorite, for: contact, in: lists, store: store)
    }
}
