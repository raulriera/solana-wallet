import Foundation
import Observation
import RPC
import Storage
import Transactions

/// Lists the addresses a window can pay: the wallet's other accounts, saved contacts, and recent payments.
///
/// Contacts and favorites come from the store that every window shares, so a change in one window shows in the others.
/// Changes show at once and save in the order they're made; a change that can't be saved sets ``error`` and is undone.
@MainActor
@Observable
final class ContactsModel {
    /// The account payments leave from; the lists never offer it.
    let sendingAccount: Address
    /// Why the latest change couldn't be saved, or `nil` while there's nothing to explain.
    var error: ContactsError?
    /// How many of the latest payments each wallet keeps on each network.
    nonisolated static let recentLimit = 10
    /// The wallet's other accounts, in wallet order, without their favorite marks.
    private let walletAccounts: [Contact]
    private let store: ContactStore
    private let services: ContactsServices
    /// Names the wallet's recent payments on the window's network.
    private let recentsKey: String
    /// The lists as last derived, so views read them without sorting and filtering on every update.
    @ObservationIgnored private var derived: Lists?

    /// Starts with the wallet's accounts; ``load()`` reads the saved contacts and recent payments.
    /// - Parameters:
    ///   - sendingAccount: The account payments leave from; it's left out of `accounts`.
    ///   - wallet: The recovery identifier of the wallet whose recent payments to list.
    ///   - network: The network whose recent payments to list.
    ///   - accounts: The wallet's accounts, in wallet order.
    ///   - store: The saved contacts and favorites that every window shares.
    ///   - services: The recent payments that every window shares.
    init(sendingAccount: Address, wallet: UUID, network: Network, accounts: [Contact] = [], store: ContactStore,
         services: ContactsServices) {
        self.sendingAccount = sendingAccount
        walletAccounts = accounts.filter { $0.address != sendingAccount }
        self.store = store
        self.services = services
        recentsKey = Self.recentsKey(wallet: wallet, network: network)
    }

    /// Names a wallet's recent payments on a network.
    /// - Parameters:
    ///   - wallet: The wallet's recovery identifier.
    ///   - network: The network.
    /// - Returns: The network's name and the wallet's identifier.
    nonisolated static func recentsKey(wallet: UUID, network: Network) -> String {
        "\(network.rawValue)/\(wallet.uuidString)"
    }

    /// The wallet's other accounts, in wallet order.
    var accounts: [Contact] { lists.accounts }
    /// Saved contacts, sorted by name.
    var contacts: [Contact] { lists.contacts }
    /// The latest landed payment to each address, newest first, saved or not.
    var payments: [RecentPayment] { lists.payments }
    /// Favorite accounts, then favorite contacts.
    var favorites: [Contact] { lists.favorites }
    /// Recent payments to addresses that aren't saved; saved ones are listed under their names instead.
    var recents: [RecentPayment] { lists.recents }
    /// Whether there's no one to list yet.
    var isEmpty: Bool { lists.isEmpty }

    /// Whether the saved contacts and payments were read, so an empty list means there's no one to list.
    var isLoaded: Bool {
        store.phase == .loaded && services.recents.phase == .loaded
    }

    /// Whether the saved contacts or payments can't be read; nothing saved is deleted or replaced.
    var isUnreadable: Bool {
        store.phase == .unreadable || services.recents.phase == .unreadable
    }

    /// Reads the saved contacts, favorites, and recent payments that weren't read yet, once the changes made before
    /// this call are saved or undone; a read that fails keeps the list as it was and sets ``isUnreadable``.
    func load() async {
        async let book: Void = store.load()
        async let recents: Void = services.recents.load()
        _ = await (book, recents)
    }

    /// The account or contact saved at an address.
    /// - Parameter address: The address to look up.
    /// - Returns: The saved account or contact, or `nil` when the address isn't saved.
    func saved(at address: Address) -> Contact? {
        lists.saved[address]
    }

    /// Whether a row lists an address: an account, a contact, or a recent payment to an unsaved address.
    /// - Parameter address: The address to look up.
    /// - Returns: `true` when the address has a row.
    func lists(_ address: Address) -> Bool {
        saved(at: address) != nil || lists.recentAddresses.contains(address)
    }

    /// The person's own history, which rules check a recipient against.
    var recipientContext: RecipientContext { lists.recipientContext }

    /// Who an address pays, with the name it's saved under.
    /// - Parameter address: The address to pay.
    /// - Returns: The recipient, named when the address is saved.
    func recipient(for address: Address) -> PaymentRecipient {
        PaymentRecipient(address: address, name: saved(at: address)?.name)
    }

    /// Saves a new contact, or replaces the saved contact with the same identity.
    /// - Parameter contact: The contact to save.
    func save(_ contact: Contact) {
        perform { [store] in try await store.save(contact) }
    }

    /// Deletes a saved contact; payments to its address move back to Recents.
    /// - Parameter contact: The contact to delete.
    func delete(_ contact: Contact) {
        perform { [store] in try await store.delete(contact) }
    }

    /// Lists a payment that landed as the latest to its address, keeping the wallet's latest ``recentLimit``
    /// payments on the window's network.
    /// - Parameter payment: The payment that landed.
    func record(_ payment: RecentPayment) {
        perform { [services, recentsKey] in
            try await services.recents.update { recents in
                recents[recentsKey] = Self.recent(recents[recentsKey] ?? [], adding: payment)
            }
        }
    }

    /// Whether an account or contact is a favorite; setting it adds the account or contact to Favorites or removes it.
    /// - Parameter contact: The account or contact.
    subscript(isFavorite contact: Contact) -> Bool {
        get { lists.favoriteIDs.contains(contact.id) }
        set {
            if accounts.contains(where: { $0.id == contact.id }) {
                perform { [store] in try await store.setFavorite(newValue, forAccountAt: contact.address) }
            } else if contacts.contains(where: { $0.id == contact.id }) {
                perform { [store] in try await store.setFavorite(newValue, for: contact) }
            }
        }
    }

    /// Makes a change at once and sets ``error`` when it can't be saved.
    /// - Parameter change: Changes the shared contacts or recent payments, which show it at once, save it in order,
    ///   and undo it when it can't be saved.
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

    /// Adds a payment as the latest to its address, keeping the latest ``recentLimit`` payments.
    /// - Parameters:
    ///   - payments: Payments, newest first.
    ///   - payment: The payment that landed last.
    /// - Returns: The payments, newest first.
    nonisolated private static func recent(_ payments: [RecentPayment],
                                           adding payment: RecentPayment) -> [RecentPayment] {
        Array(([payment] + payments.filter { $0.address != payment.address }).prefix(recentLimit))
    }

    /// The lists for the shared address book and recent payments, derived again only after either changes.
    private var lists: Lists {
        let addressBook = store.addressBook
        let payments = services.recents.value[recentsKey] ?? []
        guard var derived, derived.addressBook == addressBook, derived.savedPayments == payments else {
            let lists = Lists(sendingAccount: sendingAccount, accounts: walletAccounts, addressBook: addressBook,
                              payments: payments)
            self.derived = lists
            return lists
        }
        // Equal values saved again keep the lists, and the next comparison finds the same buffers at once.
        derived.addressBook = addressBook
        derived.savedPayments = payments
        self.derived = derived
        return derived
    }

    /// Orders contacts by name as Finder does, ignoring case and comparing numbers by value.
    /// - Parameters:
    ///   - first: A contact.
    ///   - second: Another contact.
    /// - Returns: `true` when `first` comes before `second`.
    private static func byName(_ first: Contact, _ second: Contact) -> Bool {
        first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    /// What views list, derived from the wallet's accounts, the address book, and the recent payments it came from.
    private struct Lists {
        /// The address book the lists came from.
        var addressBook: AddressBook
        /// The recent payments the lists came from, as saved.
        var savedPayments: [RecentPayment]
        let accounts: [Contact]
        let contacts: [Contact]
        let payments: [RecentPayment]
        let favorites: [Contact]
        let recents: [RecentPayment]
        let isEmpty: Bool
        /// Each saved account and contact by address; an account wins over a contact at the same address.
        let saved: [Address: Contact]
        /// The identities of the favorite accounts and contacts.
        let favoriteIDs: Set<UUID>
        /// The addresses under Recents.
        let recentAddresses: Set<Address>
        let recipientContext: RecipientContext

        /// Marks favorite accounts, sorts contacts by name and payments newest first, and lists favorites, unsaved
        /// recents, and the addresses rules check a recipient against.
        /// - Parameters:
        ///   - sendingAccount: The account payments leave from.
        ///   - walletAccounts: The wallet's other accounts, in wallet order.
        ///   - addressBook: The saved contacts and favorite accounts.
        ///   - payments: The wallet's recent payments on the window's network.
        init(sendingAccount: Address, accounts walletAccounts: [Contact], addressBook: AddressBook,
             payments: [RecentPayment]) {
            self.addressBook = addressBook
            savedPayments = payments
            accounts = walletAccounts.map { account in
                var account = account
                account.isFavorite = addressBook.favoriteAccounts.contains(account.address)
                return account
            }
            contacts = addressBook.contacts.sorted(by: ContactsModel.byName)
            self.payments = payments.sorted { $0.date > $1.date }
            favorites = (accounts + contacts).filter(\.isFavorite)
            let saved = Dictionary((accounts + contacts).map { ($0.address, $0) }) { account, _ in account }
            self.saved = saved
            favoriteIDs = Set(favorites.map(\.id))
            recents = self.payments.filter { saved[$0.address] == nil }
            recentAddresses = Set(recents.map(\.address))
            isEmpty = accounts.isEmpty && contacts.isEmpty && recents.isEmpty
            recipientContext = RecipientContext(
                knownAddresses: [sendingAccount] + accounts.map(\.address) + contacts.map(\.address)
                    + self.payments.map(\.address),
                paidAddresses: Set(self.payments.map(\.address)))
        }
    }
}
