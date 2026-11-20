import Foundation
import Observation
import Storage
import Transactions

/// The saved contacts and favorite accounts.
@MainActor
@Observable
final class ContactStore: Erasable {
    private let book: PersistentValue<AddressBook>

    /// Creates a store without reading the address book.
    ///
    /// - Parameter storage: The storage that keeps the address book.
    init(storage: any ValueStoring<AddressBook>) {
        book = PersistentValue(storage: storage, empty: AddressBook())
    }

    /// Creates a store of the address book file in a directory without reading it.
    ///
    /// - Parameter directory: The directory of the file.
    convenience init(directory: URL) {
        self.init(storage: FileItem(url: directory.appending(path: "contacts.json"),
                                    coding: .json(AddressBook.self, version: 1, unusable: .unreadable)))
    }

    /// The address book, or an empty one before it's read.
    var addressBook: AddressBook { book.value }

    var phase: PersistentValuePhase { book.phase }

    /// Reads the address book, unless it was already read.
    func load() async {
        await book.load()
    }

    /// Saves a contact, replacing the saved contact with the same identifier.
    ///
    /// - Parameter contact: The contact to save.
    /// - Throws: A storage error.
    func save(_ contact: Contact) async throws {
        try await book.update { $0.save(contact) }
    }

    /// Deletes a saved contact.
    ///
    /// - Parameter contact: The contact to delete.
    /// - Throws: A storage error.
    func delete(_ contact: Contact) async throws {
        try await book.update { $0.delete(contact) }
    }

    /// Adds a saved contact to Favorites or removes it.
    ///
    /// - Parameters:
    ///   - isFavorite: Whether the contact shows under Favorites.
    ///   - contact: The saved contact.
    /// - Throws: A storage error.
    func setFavorite(_ isFavorite: Bool, for contact: Contact) async throws {
        try await book.update { $0.setFavorite(isFavorite, for: contact) }
    }

    /// Adds an account to Favorites or removes it.
    ///
    /// - Parameters:
    ///   - isFavorite: Whether the account shows under Favorites.
    ///   - account: The account's address.
    /// - Throws: A storage error.
    func setFavorite(_ isFavorite: Bool, forAccountAt account: Address) async throws {
        try await book.update { $0.setFavorite(isFavorite, forAccountAt: account) }
    }

    func erase() async throws {
        try await book.erase()
    }
}
