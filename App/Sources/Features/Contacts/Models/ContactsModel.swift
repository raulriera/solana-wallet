import Foundation
import Observation
import RPC
import Transactions

/// Owns the addresses a window can pay: the wallet's other accounts, saved contacts, and recent payments.
///
/// Changes show at once and save in the order they're made; a change that can't be saved sets ``error``, and the list
/// returns to what's saved.
@MainActor
@Observable
final class ContactsModel {
    /// The account payments leave from; the lists never offer it.
    let sendingAccount: Address
    /// The wallet's other accounts, in wallet order.
    private(set) var accounts: [Contact] {
        didSet { updateLists() }
    }
    /// Saved contacts, sorted by name.
    private(set) var contacts: [Contact] {
        didSet { updateLists() }
    }
    /// The latest landed payment to each address, newest first, saved or not.
    private(set) var payments: [RecentPayment] {
        didSet { updateLists() }
    }
    /// Favorite accounts, then favorite contacts.
    private(set) var favorites: [Contact] = []
    /// Recent payments to addresses that aren't saved; saved ones are listed under their names instead.
    private(set) var recents: [RecentPayment] = []
    /// Whether there's no one to list yet.
    private(set) var isEmpty = true
    /// Whether the saved contacts and payments were read, so an empty list means there's no one to list.
    private(set) var isLoaded = false
    /// Whether the saved contacts or payments can't be read; nothing saved is deleted or replaced.
    private(set) var isUnreadable = false
    /// Why the latest change couldn't be saved, or `nil` while there's nothing to explain.
    var error: ContactsError?
    /// How many of the latest payments each wallet keeps on each network.
    nonisolated static let recentLimit = 10
    private let services: ContactsServices
    /// Names the wallet's recent payments on the window's network.
    private let recentsKey: String
    /// The latest change being saved, which runs after the changes made before it.
    @ObservationIgnored private var saving: Task<Void, Never>?

    /// Starts with the wallet's accounts; ``load()`` reads the saved contacts and recent payments.
    /// - Parameters:
    ///   - sendingAccount: The account payments leave from; it's left out of `accounts`.
    ///   - wallet: The recovery identifier of the wallet whose recent payments to list.
    ///   - network: The network whose recent payments to list.
    ///   - accounts: The wallet's accounts, in wallet order.
    ///   - services: The saved contacts and recent payments that every window shares.
    init(sendingAccount: Address, wallet: UUID, network: Network, accounts: [Contact] = [],
         services: ContactsServices) {
        self.sendingAccount = sendingAccount
        self.accounts = accounts.filter { $0.address != sendingAccount }
        contacts = []
        payments = []
        self.services = services
        recentsKey = Self.recentsKey(wallet: wallet, network: network)
        updateLists()
    }

    /// Names a wallet's recent payments on a network.
    /// - Parameters:
    ///   - wallet: The wallet's recovery identifier.
    ///   - network: The network.
    /// - Returns: The network's name and the wallet's identifier.
    nonisolated static func recentsKey(wallet: UUID, network: Network) -> String {
        "\(network.rawValue)/\(wallet.uuidString)"
    }

    /// Reads the saved contacts, favorites, and recent payments once the changes being saved finish; a read that
    /// fails keeps the list as it was and sets ``isUnreadable``.
    func load() async {
        await saving?.value
        do {
            async let book = services.addressBook.load()
            async let recents = services.recents.load()
            let (savedBook, savedRecents) = try await (book, recents)
            let addressBook = savedBook ?? AddressBook()
            accounts = accounts.map { account in
                var account = account
                account.isFavorite = addressBook.favoriteAccounts.contains(account.address)
                return account
            }
            contacts = addressBook.contacts.sorted(by: Self.byName)
            payments = (savedRecents?[recentsKey] ?? []).sorted { $0.date > $1.date }
            isUnreadable = false
            isLoaded = true
        } catch is CancellationError {
            // A window that went away doesn't need the list.
        } catch {
            isUnreadable = true
        }
    }

    /// The account or contact saved at an address.
    /// - Parameter address: The address to look up.
    /// - Returns: The saved account or contact, or `nil` when the address isn't saved.
    func saved(at address: Address) -> Contact? {
        accounts.first { $0.address == address } ?? contacts.first { $0.address == address }
    }

    /// Whether a row lists an address: an account, a contact, or a recent payment to an unsaved address.
    /// - Parameter address: The address to look up.
    /// - Returns: `true` when the address has a row.
    func lists(_ address: Address) -> Bool {
        saved(at: address) != nil || recents.contains { $0.address == address }
    }

    /// The person's own history, which rules check a recipient against.
    var recipientContext: RecipientContext {
        RecipientContext(knownAddresses: [sendingAccount] + accounts.map(\.address) + contacts.map(\.address)
                            + payments.map(\.address),
                         paidAddresses: Set(payments.map(\.address)))
    }

    /// Who an address pays, with the name it's saved under.
    /// - Parameter address: The address to pay.
    /// - Returns: The recipient, named when the address is saved.
    func recipient(for address: Address) -> PaymentRecipient {
        PaymentRecipient(address: address, name: saved(at: address)?.name)
    }

    /// Saves a new contact, or replaces the saved contact with the same identity.
    /// - Parameter contact: The contact to save.
    func save(_ contact: Contact) {
        // One assignment, so the lists update once.
        var updated = contacts.filter { $0.id != contact.id }
        updated.append(contact)
        contacts = updated.sorted(by: Self.byName)
        persist(services.addressBook, from: AddressBook()) { $0.save(contact) }
    }

    /// Deletes a saved contact; payments to its address move back to Recents.
    /// - Parameter contact: The contact to delete.
    func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        persist(services.addressBook, from: AddressBook()) { $0.delete(contact) }
    }

    /// Lists a payment that landed as the latest to its address, keeping the wallet's latest ``recentLimit``
    /// payments on the window's network.
    /// - Parameter payment: The payment that landed.
    func record(_ payment: RecentPayment) {
        payments = Self.recent(payments, adding: payment)
        persist(services.recents, from: [:]) { [recentsKey] recents in
            recents[recentsKey] = Self.recent(recents[recentsKey] ?? [], adding: payment)
        }
    }

    /// Whether an account or contact is a favorite; setting it adds the account or contact to Favorites or removes it.
    /// - Parameter contact: The account or contact.
    subscript(isFavorite contact: Contact) -> Bool {
        get {
            accounts.first { $0.id == contact.id }?.isFavorite
                ?? contacts.first { $0.id == contact.id }?.isFavorite
                ?? false
        }
        set {
            if let index = accounts.firstIndex(where: { $0.id == contact.id }) {
                accounts[index].isFavorite = newValue
                persist(services.addressBook, from: AddressBook()) {
                    $0.setFavorite(newValue, forAccountAt: contact.address)
                }
            } else if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
                contacts[index].isFavorite = newValue
                persist(services.addressBook, from: AddressBook()) { $0.setFavorite(newValue, for: contact) }
            }
        }
    }

    /// Saves a change after the changes made before it, then tells every window to read what's saved, which also
    /// undoes a change that couldn't be saved here.
    /// - Parameters:
    ///   - store: The storage that keeps the changed value.
    ///   - empty: The value to change before one is saved.
    ///   - change: Changes the saved value.
    private func persist<Value: Equatable & Sendable>(
        _ store: any ValueStoring<Value>, from empty: Value, _ change: @escaping @Sendable (inout Value) -> Void
    ) {
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                try await store.update { saved in
                    var value = saved ?? empty
                    change(&value)
                    saved = value
                }
            } catch {
                self.error = .unsaved
            }
            services.revision.advance()
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

    /// Lists favorites and unsaved recents again, and whether anyone is listed, after the accounts, contacts, or
    /// payments change, so views read them without filtering on every update.
    private func updateLists() {
        favorites = (accounts + contacts).filter(\.isFavorite)
        recents = payments.filter { saved(at: $0.address) == nil }
        isEmpty = accounts.isEmpty && contacts.isEmpty && recents.isEmpty
    }

    /// Orders contacts by name as Finder does, ignoring case and comparing numbers by value.
    /// - Parameters:
    ///   - first: A contact.
    ///   - second: Another contact.
    /// - Returns: `true` when `first` comes before `second`.
    private static func byName(_ first: Contact, _ second: Contact) -> Bool {
        first.name.localizedStandardCompare(second.name) == .orderedAscending
    }
}
