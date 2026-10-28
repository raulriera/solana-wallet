import Foundation
import Storage
import Transactions

/// What the contacts tab lists for an account on a network: the wallet's other accounts, saved contacts, favorites, and
/// recent payments, and the person's own history that rules check a recipient against.
nonisolated struct ContactLists: Sendable {
    /// The account payments leave from; the lists never offer it.
    let sendingAccount: Address
    /// The records of every account in the wallet on the network, whose payments are listed.
    let keys: [TransactionRecord.Key]
    /// The wallet's other accounts, in wallet order.
    let accounts: [Contact]
    /// Saved contacts, sorted by name.
    let contacts: [Contact]
    /// The latest landed payment to each address, newest first, saved or not.
    let payments: [RecentPayment]
    /// Favorite accounts, then favorite contacts.
    let favorites: [Contact]
    /// Recent payments to addresses that aren't saved; saved ones are listed under their names instead.
    let recents: [RecentPayment]
    /// The person's own history, which rules check a recipient against.
    let recipientContext: RecipientContext
    /// Whether the saved contacts and records were read, or can't be.
    private let phase: PersistentValuePhase
    /// Each saved account and contact by address; an account wins over a contact at the same address.
    private let saved: [Address: Contact]
    /// The addresses under Recents.
    private let recentAddresses: Set<Address>

    /// Marks favorite accounts, sorts contacts by name, and lists favorites, unsaved recents, and the addresses rules
    /// check a recipient against.
    /// - Parameters:
    ///   - sendingAccount: The account payments leave from.
    ///   - accounts: The wallet's other accounts, in wallet order, without their favorite marks.
    ///   - addressBook: The saved contacts and favorite accounts.
    ///   - payments: The wallet's recent payments on the network, newest first.
    ///   - keys: The records whose payments are listed.
    ///   - phase: Whether the saved contacts and records were read, or can't be.
    init(sendingAccount: Address, accounts: [Contact], addressBook: AddressBook, payments: [RecentPayment],
         keys: [TransactionRecord.Key], phase: PersistentValuePhase) {
        self.sendingAccount = sendingAccount
        self.keys = keys
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
        recents = payments.filter { saved[$0.address] == nil }
        recentAddresses = Set(recents.map(\.address))
        recipientContext = RecipientContext(
            knownAddresses: [sendingAccount] + self.accounts.map(\.address) + contacts.map(\.address)
                + payments.map(\.address),
            paidAddresses: Set(payments.map(\.address)))
    }

    /// Whether the saved contacts and payments were read, so an empty list means there's no one to list.
    var isLoaded: Bool { phase == .loaded }

    /// Whether the saved contacts or payments can't be read; nothing saved is deleted or replaced.
    var isUnreadable: Bool { phase == .unreadable }

    /// Whether there's no one to list yet.
    var isEmpty: Bool { accounts.isEmpty && contacts.isEmpty && recents.isEmpty }

    /// The account or contact saved at an address.
    /// - Parameter address: The address to look up.
    /// - Returns: The saved account or contact, or `nil` when the address isn't saved.
    func saved(at address: Address) -> Contact? {
        saved[address]
    }

    /// Whether a row lists an address: an account, a contact, or a recent payment to an unsaved address.
    /// - Parameter address: The address to look up.
    /// - Returns: `true` when the address has a row.
    func lists(_ address: Address) -> Bool {
        saved[address] != nil || recentAddresses.contains(address)
    }

    /// Whether a row still lists a contact's address once the contact is deleted: an account at it, or a payment to it.
    /// - Parameter contact: The saved contact.
    /// - Returns: `true` when the address keeps a row.
    func keepsRow(afterDeleting contact: Contact) -> Bool {
        accounts.contains { $0.address == contact.address } || payments.contains { $0.address == contact.address }
    }

    /// Who an address pays, with the name it's saved under.
    /// - Parameter address: The address to pay.
    /// - Returns: The recipient, named when the address is saved.
    func recipient(for address: Address) -> PaymentRecipient {
        PaymentRecipient(address: address, name: saved(at: address)?.name)
    }
}
