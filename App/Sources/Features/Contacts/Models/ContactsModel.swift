import Foundation
import Observation
import RPC
import Storage
import Transactions

/// Lists the addresses an account can pay on a network, and saves the changes the person makes to contacts and
/// favorites.
///
/// Contacts and favorites come from the store that every window shares, so a change in one window shows in the others.
/// Changes show at once and save in the order they're made; a change that can't be saved sets ``error`` and is undone.
/// Recent payments are the succeeded payments of every account in the wallet on the network, which the shared
/// transactions record, so a payment that lands shows in every window.
@MainActor
@Observable
final class ContactsModel {
    /// Why the latest change couldn't be saved, or `nil` while there's nothing to explain.
    var error: ContactsError?
    /// How many recent payments the lists show.
    nonisolated static let recentLimit = 10
    /// The lists as last derived, so views read them without sorting and filtering on every update.
    @ObservationIgnored private var derived: (source: Source, lists: ContactLists)?

    /// The lists an account can pay from on a network, derived again only after what they come from changes.
    /// - Parameters:
    ///   - account: The account payments leave from; it's left out of the listed accounts.
    ///   - network: The network whose recent payments to list.
    ///   - wallet: The wallet's accounts, in wallet order, whose payments are listed with the sending account's.
    ///   - store: The saved contacts and favorites that every window shares.
    ///   - transactions: The transactions that every window sends, watches, and records.
    /// - Returns: The lists.
    func lists(for account: Account, on network: Network, in wallet: [Account], store: ContactStore,
               transactions: TransactionStore) -> ContactLists {
        let others = wallet.filter { $0.address != account.address }
        let keys = ([account] + others).map { TransactionRecord.Key(account: $0.id, network: network) }
        let phases = [store.phase] + keys.map(transactions.phase(for:))
        let source = Source(keys: keys, accounts: others, addressBook: store.addressBook,
                            records: keys.map(transactions.records(for:)), phases: phases)
        if let derived, derived.source == source {
            // Equal values saved again keep the lists, and the next comparison finds the same buffers at once.
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

    /// Reads the saved contacts, favorites, and the records that weren't read yet, once the changes made before this
    /// call are saved or undone; a read that fails keeps the lists as they were and makes them unreadable.
    /// - Parameters:
    ///   - keys: The records whose payments are listed.
    ///   - store: The saved contacts and favorites that every window shares.
    ///   - transactions: The transactions that every window sends, watches, and records.
    func load(_ keys: [TransactionRecord.Key], from store: ContactStore, transactions: TransactionStore) async {
        async let book: Void = store.load()
        async let records: Void = withDiscardingTaskGroup { group in
            for key in keys {
                group.addTask { await transactions.load(key) }
            }
        }
        _ = await (book, records)
    }

    /// Saves a new contact, or replaces the saved contact with the same identity.
    /// - Parameters:
    ///   - contact: The contact to save.
    ///   - store: The saved contacts that every window shares.
    func save(_ contact: Contact, in store: ContactStore) {
        perform { try await store.save(contact) }
    }

    /// Deletes a saved contact; payments to its address move back to Recents.
    /// - Parameters:
    ///   - contact: The contact to delete.
    ///   - store: The saved contacts that every window shares.
    func delete(_ contact: Contact, from store: ContactStore) {
        perform { try await store.delete(contact) }
    }

    /// Adds a listed account or contact to Favorites or removes it; an address the lists don't save changes nothing.
    /// - Parameters:
    ///   - isFavorite: Whether the account or contact shows under Favorites.
    ///   - contact: The listed account or contact.
    ///   - lists: The lists that show it.
    ///   - store: The saved favorites that every window shares.
    func setFavorite(_ isFavorite: Bool, for contact: Contact, in lists: ContactLists, store: ContactStore) {
        if lists.accounts.contains(where: { $0.id == contact.id }) {
            perform { try await store.setFavorite(isFavorite, forAccountAt: contact.address) }
        } else if lists.contacts.contains(where: { $0.id == contact.id }) {
            perform { try await store.setFavorite(isFavorite, for: contact) }
        }
    }

    /// Makes a change at once and sets ``error`` when it can't be saved.
    /// - Parameter change: Changes the shared contacts, which show it at once, save it in order, and undo it when it
    ///   can't be saved.
    private func perform(_ change: @escaping @MainActor () async throws -> Void) {
        // Runs at once, so the change shows before this method returns.
        Task.immediate {
            do {
                try await change()
            } catch {
                self.error = .unsaved
            }
        }
    }

    /// What the lists were derived from, so equal sources reuse them.
    private struct Source: Equatable {
        /// The records of the sending account, then of the wallet's other accounts, on the network.
        let keys: [TransactionRecord.Key]
        /// The wallet's other accounts, whose names and order the lists show.
        let accounts: [Account]
        let addressBook: AddressBook
        /// Each account's records that the payments come from, as the shared transactions keep them.
        let records: [[TransactionRecord]]
        /// Whether the address book and each account's records were read.
        let phases: [PersistentValuePhase]
    }
}
