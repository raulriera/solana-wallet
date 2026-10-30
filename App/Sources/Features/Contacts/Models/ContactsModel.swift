import Foundation
import Observation
import RPC
import Storage
import Transactions

/// A model that lists the addresses an account can pay and saves changes to contacts and favorites.
@MainActor
@Observable
final class ContactsModel {
    var error: ContactsError?
    /// The number of recent payments the lists show.
    nonisolated static let recentLimit = 10
    @ObservationIgnored private var derived: (source: Source, lists: ContactLists)?

    /// Returns the lists of the addresses an account can pay on a network.
    ///
    /// - Parameters:
    ///   - account: The account that pays.
    ///   - network: The network of the recent payments.
    ///   - wallet: The wallet's accounts.
    ///   - store: The store of contacts and favorites.
    ///   - transactions: The store that records transactions.
    /// - Returns: The lists.
    func lists(for account: Account, on network: Network, in wallet: [Account], store: ContactStore,
               transactions: TransactionStore) -> ContactLists {
        let others = wallet.filter { $0.address != account.address }
        let keys = ([account] + others).map { TransactionRecord.Key(account: $0.id, network: network) }
        let phases = [store.phase] + keys.map(transactions.phase(for:))
        let source = Source(keys: keys, accounts: others, addressBook: store.addressBook,
                            records: keys.map(transactions.records(for:)), phases: phases)
        if let derived, derived.source == source {
            self.derived = (source, derived.lists)
            return derived.lists
        }
        let payments = transactions.recentPayments(for: keys, limit: Self.recentLimit).compactMap(RecentPayment.init)
        let phase: PersistentValuePhase = if phases.contains(.unreadable) {
            .unreadable
        } else if phases.allSatisfy({ $0 == .loaded }) {
            .loaded
        } else {
            .loading
        }
        let lists = ContactLists(sendingAccount: account.address, accounts: others.map(Contact.init),
                                 addressBook: source.addressBook, payments: payments, keys: keys, phase: phase)
        derived = (source, lists)
        return lists
    }

    /// Reads the saved contacts, favorites, and records.
    ///
    /// - Parameters:
    ///   - keys: The keys of the records to read.
    ///   - store: The store of contacts and favorites.
    ///   - transactions: The store that records transactions.
    func load(_ keys: [TransactionRecord.Key], from store: ContactStore, transactions: TransactionStore) async {
        async let book: Void = store.load()
        async let records: Void = withDiscardingTaskGroup { group in
            for key in keys {
                group.addTask { await transactions.load(key) }
            }
        }
        _ = await (book, records)
    }

    /// Saves a contact, replacing the saved contact with the same identifier.
    ///
    /// - Parameters:
    ///   - contact: The contact to save.
    ///   - store: The store of contacts.
    func save(_ contact: Contact, in store: ContactStore) {
        perform { try await store.save(contact) }
    }

    /// Deletes a saved contact.
    ///
    /// - Parameters:
    ///   - contact: The contact to delete.
    ///   - store: The store of contacts.
    func delete(_ contact: Contact, from store: ContactStore) {
        perform { try await store.delete(contact) }
    }

    /// Adds a listed account or contact to Favorites or removes it.
    ///
    /// - Parameters:
    ///   - isFavorite: Whether the account or contact shows under Favorites.
    ///   - contact: The listed account or contact.
    ///   - lists: The lists that show it.
    ///   - store: The store of favorites.
    func setFavorite(_ isFavorite: Bool, for contact: Contact, in lists: ContactLists, store: ContactStore) {
        if lists.accounts.contains(where: { $0.id == contact.id }) {
            perform { try await store.setFavorite(isFavorite, forAccountAt: contact.address) }
        } else if lists.contacts.contains(where: { $0.id == contact.id }) {
            perform { try await store.setFavorite(isFavorite, for: contact) }
        }
    }

    /// Makes a change and sets ``error`` when it can't be saved.
    ///
    /// - Parameter change: The change to the saved contacts.
    private func perform(_ change: @escaping @MainActor () async throws -> Void) {
        Task.immediate {
            do {
                try await change()
            } catch {
                self.error = .unsaved
            }
        }
    }

    /// The values that the lists are derived from.
    private struct Source: Equatable {
        let keys: [TransactionRecord.Key]
        /// The wallet's other accounts.
        let accounts: [Account]
        let addressBook: AddressBook
        let records: [[TransactionRecord]]
        let phases: [PersistentValuePhase]
    }
}
