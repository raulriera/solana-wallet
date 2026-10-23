import Foundation
import Observation
import Transactions

/// Owns the addresses a window can pay: the wallet's other accounts, saved contacts, and recent payments.
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

    /// Starts with the wallet's accounts, saved contacts, and recent payments.
    /// - Parameters:
    ///   - sendingAccount: The account payments leave from; it's left out of `accounts`.
    ///   - accounts: The wallet's accounts, in wallet order.
    ///   - contacts: Saved contacts, in any order.
    ///   - payments: The latest landed payment to each address, in any order.
    init(sendingAccount: Address, accounts: [Contact] = [], contacts: [Contact] = [], payments: [RecentPayment] = []) {
        self.sendingAccount = sendingAccount
        self.accounts = accounts.filter { $0.address != sendingAccount }
        self.contacts = contacts.sorted(by: Self.byName)
        self.payments = payments.sorted { $0.date > $1.date }
        updateLists()
    }

    /// The account or contact saved at an address.
    /// - Parameter address: The address to look up.
    /// - Returns: The saved account or contact, or `nil` when the address isn't saved.
    func saved(at address: Address) -> Contact? {
        accounts.first { $0.address == address } ?? contacts.first { $0.address == address }
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
    }

    /// Deletes a saved contact; payments to its address move back to Recents.
    /// - Parameter contact: The contact to delete.
    func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
    }

    /// Adds an account or contact to Favorites, or removes it.
    /// - Parameter contact: The account or contact.
    func toggleFavorite(_ contact: Contact) {
        if let index = accounts.firstIndex(where: { $0.id == contact.id }) {
            accounts[index].isFavorite.toggle()
        } else if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index].isFavorite.toggle()
        }
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
