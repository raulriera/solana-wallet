import Foundation
import Observation
import Storage
import Transactions

/// The saved contacts and favorites that every window shares, so a change in one window shows in the others at once.
///
/// The store reads nothing until ``load()``. Each change shows at once and saves after the changes made before it; a
/// change that can't be saved is undone and throws.
@MainActor
@Observable
final class ContactStore {
    private let book: PersistentValue<AddressBook>

    /// Connects to the storage that keeps the address book, without reading it.
    /// - Parameter storage: The storage that keeps the address book.
    init(storage: any ValueStoring<AddressBook>) {
        book = PersistentValue(storage: storage, empty: AddressBook())
    }

    /// Connects to the address book's file in a directory, without reading it.
    /// - Parameter directory: The directory that keeps the Contacts files.
    convenience init(directory: URL) {
        self.init(storage: FileItem(url: directory.appending(path: "contacts.json"), coding: .json(AddressBook.self)))
    }

    /// The saved contacts and favorites with every change made so far, or an empty address book before it's read.
    var addressBook: AddressBook { book.value }

    /// Whether the address book was read.
    var phase: PersistentValuePhase { book.phase }

    /// Reads the address book, unless it was already read, and returns once the changes made before this call are saved
    /// or undone.
    func load() async {
        await book.load()
    }

    /// Saves a new contact, or replaces the saved contact with the same identity.
    /// - Parameter contact: The contact to save.
    /// - Throws: A storage error after undoing the change.
    func save(_ contact: Contact) async throws {
        try await book.update { $0.save(contact) }
    }

    /// Deletes a saved contact.
    /// - Parameter contact: The contact to delete.
    /// - Throws: A storage error after undoing the change.
    func delete(_ contact: Contact) async throws {
        try await book.update { $0.delete(contact) }
    }

    /// Adds a saved contact to Favorites or removes it.
    /// - Parameters:
    ///   - isFavorite: Whether the contact shows under Favorites.
    ///   - contact: The saved contact.
    /// - Throws: A storage error after undoing the change.
    func setFavorite(_ isFavorite: Bool, for contact: Contact) async throws {
        try await book.update { $0.setFavorite(isFavorite, for: contact) }
    }

    /// Adds an account to Favorites or removes it.
    /// - Parameters:
    ///   - isFavorite: Whether the account shows under Favorites.
    ///   - account: The account's address.
    /// - Throws: A storage error after undoing the change.
    func setFavorite(_ isFavorite: Bool, forAccountAt account: Address) async throws {
        try await book.update { $0.setFavorite(isFavorite, forAccountAt: account) }
    }

    /// Deletes the saved address book after the changes made before it, so every window forgets the contacts.
    /// - Throws: A storage error, which keeps the address book.
    func erase() async throws {
        try await book.erase()
    }
}
