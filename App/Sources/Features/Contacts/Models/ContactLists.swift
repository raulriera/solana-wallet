import Foundation
import Storage
import Transactions

/// The addresses an account can pay on a network: other accounts, contacts, favorites, and recent payments.
nonisolated struct ContactLists: Sendable {
    /// The address of the account that pays.
    let sendingAccount: Address
    /// The wallet's other accounts.
    let accounts: [Contact]
    /// The saved contacts, sorted by name.
    let contacts: [Contact]
    /// The latest payment to each address, newest first.
    let payments: [RecentPayment]
    /// The favorite accounts, then the favorite contacts.
    let favorites: [Contact]
    /// The recent payments to unsaved addresses, without the account that pays.
    let recents: [RecentPayment]
    let recipientContext: RecipientContext
    private let phase: PersistentValuePhase
    /// The saved accounts and contacts by address, where an account takes precedence over a contact.
    private let saved: [Address: Contact]
    private let recentAddresses: Set<Address>

    /// Creates the lists of the addresses an account can pay.
    ///
    /// - Parameters:
    ///   - sendingAccount: The address of the account that pays.
    ///   - accounts: The wallet's other accounts, without their favorite marks.
    ///   - addressBook: The saved contacts and favorite accounts.
    ///   - payments: The recent payments, newest first.
    ///   - phase: Whether the saved contacts and payments were read.
    init(sendingAccount: Address, accounts: [Contact], addressBook: AddressBook, payments: [RecentPayment],
         phase: PersistentValuePhase) {
        self.sendingAccount = sendingAccount
        self.phase = phase
        self.accounts = accounts.map { account in
            var account = account
            account.isFavorite = addressBook.favoriteAccounts.contains(account.address)
            return account
        }
        contacts = addressBook.contacts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.payments = payments
        favorites = (self.accounts + contacts).filter(\.isFavorite)
        let saved = Dictionary((self.accounts + contacts).map { ($0.address, $0) }) { account, _ in account }
        self.saved = saved
        recents = payments.filter { saved[$0.address] == nil && $0.address != sendingAccount }
        recentAddresses = Set(recents.map(\.address))
        recipientContext = RecipientContext(
            knownAddresses: [sendingAccount] + self.accounts.map(\.address) + contacts.map(\.address)
                + payments.map(\.address),
            paidAddresses: Set(payments.map(\.address)))
    }

    var isLoaded: Bool { phase == .loaded }

    var isUnreadable: Bool { phase == .unreadable }

    var isEmpty: Bool { accounts.isEmpty && contacts.isEmpty && recents.isEmpty }

    /// Returns the account or contact saved at an address.
    ///
    /// - Parameter address: The address to look up.
    /// - Returns: The saved account or contact, or `nil` when the address isn't saved.
    func saved(at address: Address) -> Contact? {
        saved[address]
    }

    /// Returns whether a row lists an address.
    ///
    /// - Parameter address: The address to look up.
    /// - Returns: `true` when the address has a row.
    func lists(_ address: Address) -> Bool {
        saved[address] != nil || recentAddresses.contains(address)
    }

    /// Returns whether a contact's address keeps a row after the contact is deleted.
    ///
    /// - Parameter contact: The saved contact.
    /// - Returns: `true` when an account or a payment keeps the address listed.
    func keepsRow(afterDeleting contact: Contact) -> Bool {
        accounts.contains { $0.address == contact.address } || payments.contains { $0.address == contact.address }
    }

    /// Returns the recipient at an address.
    ///
    /// - Parameter address: The address to pay.
    /// - Returns: The recipient, named when the address is saved.
    func recipient(for address: Address) -> PaymentRecipient {
        PaymentRecipient(address: address, name: saved(at: address)?.name)
    }
}
