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
    @ObservationIgnored private var derived: (source: Source, lists: ContactLists)?

    /// Returns the lists of the addresses an account can pay on a network.
    ///
    /// - Parameters:
    ///   - account: The account that pays.
    ///   - network: The network of the recent payments.
    ///   - wallet: The wallet's accounts.
    ///   - store: The store of contacts and favorites.
    ///   - recents: The store of recent payments.
    /// - Returns: The lists.
    func lists(for account: Account, on network: Network, in wallet: [Account], store: ContactStore,
               recents: RecentPaymentStore) -> ContactLists {
        let phases = [store.phase, recents.phase]
        let source = Source(sendingAccount: account.address,
                            accounts: wallet.filter { $0.address != account.address },
                            addressBook: store.addressBook, payments: recents.payments(on: network), phases: phases)
        if let derived, derived.source == source {
            self.derived = (source, derived.lists)
            return derived.lists
        }
        let lists = ContactLists(sendingAccount: source.sendingAccount, accounts: source.accounts.map(Contact.init),
                                 addressBook: source.addressBook, payments: source.payments,
                                 phase: PersistentValuePhase(combining: phases))
        derived = (source, lists)
        return lists
    }

    /// Reads the saved contacts, favorites, and recent payments.
    ///
    /// - Parameters:
    ///   - store: The store of contacts and favorites.
    ///   - recents: The store of recent payments.
    func load(from store: ContactStore, recents: RecentPaymentStore) async {
        async let book: Void = store.load()
        async let payments: Void = recents.load()
        _ = await (book, payments)
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
        /// The address of the account that pays.
        let sendingAccount: Address
        /// The wallet's other accounts.
        let accounts: [Account]
        let addressBook: AddressBook
        let payments: [RecentPayment]
        let phases: [PersistentValuePhase]
    }
}
