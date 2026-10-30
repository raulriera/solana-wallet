import Foundation
import Transactions

/// The saved contacts and favorite accounts of every wallet and network.
nonisolated struct AddressBook: Codable, Equatable, Sendable {
    private(set) var contacts: [Contact] = []
    private(set) var favoriteAccounts: Set<Address> = []

    /// Creates an empty address book.
    init() {}

    /// Saves a contact, replacing the saved contact with the same identifier.
    ///
    /// - Parameter contact: The contact to save.
    mutating func save(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        contacts.append(contact)
    }

    /// Deletes a saved contact.
    ///
    /// - Parameter contact: The contact to delete.
    mutating func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
    }

    /// Adds a saved contact to Favorites or removes it.
    ///
    /// - Parameters:
    ///   - isFavorite: Whether the contact shows under Favorites.
    ///   - contact: The saved contact.
    mutating func setFavorite(_ isFavorite: Bool, for contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index].isFavorite = isFavorite
    }

    /// Adds an account to Favorites or removes it.
    ///
    /// - Parameters:
    ///   - isFavorite: Whether the account shows under Favorites.
    ///   - account: The account's address.
    mutating func setFavorite(_ isFavorite: Bool, forAccountAt account: Address) {
        if isFavorite { favoriteAccounts.insert(account) } else { favoriteAccounts.remove(account) }
    }
}
