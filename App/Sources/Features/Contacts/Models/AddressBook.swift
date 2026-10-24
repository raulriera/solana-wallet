import Foundation
import Transactions

/// The saved contacts and favorites, which every wallet and network shares.
nonisolated struct AddressBook: Codable, Equatable, Sendable {
    /// Saved contacts, in the order they were saved.
    private(set) var contacts: [Contact] = []
    /// The addresses of the wallets' accounts that show under Favorites.
    private(set) var favoriteAccounts: Set<Address> = []

    /// Creates an empty address book.
    init() {}

    /// Saves a new contact, or replaces the saved contact with the same identity.
    /// - Parameter contact: The contact to save.
    mutating func save(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        contacts.append(contact)
    }

    /// Deletes a saved contact; a contact that isn't saved is already deleted.
    /// - Parameter contact: The contact to delete.
    mutating func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
    }

    /// Adds a saved contact to Favorites or removes it; a contact that isn't saved stays unsaved.
    /// - Parameters:
    ///   - isFavorite: Whether the contact shows under Favorites.
    ///   - contact: The saved contact.
    mutating func setFavorite(_ isFavorite: Bool, for contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].isFavorite = isFavorite
    }

    /// Adds an account to Favorites or removes it.
    /// - Parameters:
    ///   - isFavorite: Whether the account shows under Favorites.
    ///   - account: The account's address.
    mutating func setFavorite(_ isFavorite: Bool, forAccountAt account: Address) {
        if isFavorite { favoriteAccounts.insert(account) } else { favoriteAccounts.remove(account) }
    }
}
