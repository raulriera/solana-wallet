import Foundation
import Observation
import RPC
import Testing
import Wallet
@testable import Transactions
@testable import widgets

/// Checks how the contacts list sorts and groups addresses, which addresses rules check against, and how it saves,
/// favorites, and deletes.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactsModelTests {
    /// The account payments leave from is never offered as a recipient.
    @Test func `The sending account isn't listed`() async {
        #expect(await ContactsFixtures.model().accounts.map(\.address) == [ContactsFixtures.savings])
    }

    /// Contacts sort by name without regard to case.
    @Test func `Contacts sort by name`() async {
        #expect(await ContactsFixtures.model().contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// Favorites list favorite accounts before favorite contacts.
    @Test func `Favorites list accounts before contacts`() async {
        #expect(await ContactsFixtures.model().favorites.map(\.name) == ["Savings", "Alice"])
    }

    /// Recents list only unsaved addresses, since saved ones show under their names.
    @Test func `Recents leave out saved addresses`() async {
        #expect(await ContactsFixtures.model().recents.map(\.address) == [ContactsFixtures.recent])
    }

    /// Payments are kept newest first.
    @Test func `Payments are newest first`() async {
        #expect(await ContactsFixtures.model().payments.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Rules check a recipient against every address the person used: accounts, contacts, and paid addresses.
    @Test func `The recipient context lists every address the person used`() async {
        let known = Set(await ContactsFixtures.model().recipientContext.knownAddresses)
        #expect(known == [ContactsFixtures.sending, ContactsFixtures.savings, ContactsFixtures.alice,
                          ContactsFixtures.bruno, ContactsFixtures.recent])
    }

    /// The first-payment rule sees only the addresses the person paid.
    @Test func `The recipient context lists the paid addresses`() async {
        #expect(await ContactsFixtures.model().recipientContext.paidAddresses == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// A saved address is paid under its name; an unsaved one has none.
    @Test func `Recipients are named only when saved`() async {
        let contacts = await ContactsFixtures.model()
        #expect(contacts.recipient(for: ContactsFixtures.alice) == PaymentRecipient(address: ContactsFixtures.alice, name: "Alice"))
        #expect(contacts.recipient(for: ContactsFixtures.recent).name == nil)
    }

    /// A saved address is found under its name; an unsaved one isn't.
    @Test func `Saved addresses are found`() async {
        let contacts = await ContactsFixtures.model()
        #expect(contacts.saved(at: ContactsFixtures.alice)?.name == "Alice")
        #expect(contacts.saved(at: ContactsFixtures.savings)?.name == "Savings")
        #expect(contacts.saved(at: ContactsFixtures.recent) == nil)
    }

    /// Accounts, contacts, and unsaved recents have rows; the sending account and unpaid strangers don't.
    @Test func `Only listed addresses have rows`() async {
        let contacts = await ContactsFixtures.model()
        #expect([ContactsFixtures.savings, ContactsFixtures.alice, ContactsFixtures.recent].allSatisfy(contacts.lists))
        #expect(!contacts.lists(ContactsFixtures.sending))
        #expect(!contacts.lists(ContactsFixtures.stranger))
    }

    /// A new contact joins the list in name order.
    @Test func `Saving a new contact keeps the list sorted`() async {
        let contacts = await ContactsFixtures.model()
        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        #expect(contacts.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
    }

    /// Saving a contact with an existing identity replaces it instead of adding another.
    @Test func `Saving an edited contact replaces it`() async throws {
        let contacts = await ContactsFixtures.model()
        var bruno = try #require(contacts.saved(at: ContactsFixtures.bruno))
        bruno.name = "Zed"
        contacts.save(bruno)
        #expect(contacts.contacts.map(\.name) == ["Alice", "Zed"])
    }

    /// Deleting a contact who was paid lists their address under Recents again.
    @Test func `Deleting a paid contact returns them to Recents`() async throws {
        let contacts = await ContactsFixtures.model()
        contacts.delete(try #require(contacts.contacts.first { $0.address == ContactsFixtures.alice }))
        #expect(contacts.contacts.map(\.address) == [ContactsFixtures.bruno])
        #expect(contacts.recents.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Accounts and contacts both join and leave Favorites.
    @Test func `Favorites toggle for accounts and contacts`() async throws {
        let contacts = await ContactsFixtures.model()
        let savings = try #require(contacts.accounts.first { $0.address == ContactsFixtures.savings })
        let bruno = try #require(contacts.contacts.first { $0.address == ContactsFixtures.bruno })
        contacts[isFavorite: savings].toggle()
        contacts[isFavorite: bruno].toggle()
        #expect(!contacts[isFavorite: savings])
        #expect(contacts[isFavorite: bruno])
        #expect(contacts.favorites.map(\.name) == ["Alice", "bruno"])
    }

    /// The wallet's other saved accounts are listed under their names, without other wallets' accounts, and one can be
    /// a favorite.
    @Test func `The wallet's other saved accounts are listed`() async throws {
        let main = widgets.Account(id: UUID(), recoveryID: ContactsFixtures.wallet, address: ContactsFixtures.sending,
                                   path: .solana)
        let savings = widgets.Account(id: UUID(), recoveryID: ContactsFixtures.wallet, address: ContactsFixtures.savings,
                                      path: try DerivationPath("m/44'/501'/1'/0'"))
        let otherWallet = widgets.Account(id: UUID(), recoveryID: UUID(), address: ContactsFixtures.bruno, path: .solana)
        let accounts = AccountStore.inMemory(StoredValue([main, otherWallet, savings]))
        await accounts.load()
        let addressBook = StoredValue<AddressBook>()
        let contacts = ContactsModel(sendingAccount: main, network: .mainnet,
                                     accounts: accounts.accounts(inWallet: ContactsFixtures.wallet),
                                     store: ContactsFixtures.store(addressBook), transactions: .unused)
        await contacts.load()

        let listed = try #require(contacts.accounts.first)
        #expect(contacts.accounts.count == 1)
        #expect(listed.id == savings.id)
        #expect(listed.address == ContactsFixtures.savings)
        #expect(listed.name == "Account 2")

        contacts[isFavorite: listed] = true
        await contacts.load()

        #expect(contacts.favorites.map(\.address) == [ContactsFixtures.savings])
        #expect(await addressBook.value?.favoriteAccounts == [ContactsFixtures.savings])
    }

    /// A wallet with only its sending account and no contacts or payments has no one to list.
    @Test func `A list without anyone else is empty`() async {
        let contacts = ContactsModel(sendingAccount: ContactsFixtures.main, network: .mainnet,
                                     accounts: [ContactsFixtures.main], store: ContactsFixtures.store(StoredValue()),
                                     transactions: .unused)

        await contacts.load()

        #expect(contacts.isLoaded)
        #expect(contacts.isEmpty)
    }

    /// New, edited, deleted, and favorite contacts and favorite accounts are read back by the next list, as after a
    /// relaunch.
    @Test func `Changes are saved for the next list`() async throws {
        let addressBook = StoredValue(ContactsFixtures.addressBook)
        let contacts = await ContactsFixtures.model(store: ContactsFixtures.store(addressBook))
        var bruno = try #require(contacts.saved(at: ContactsFixtures.bruno))
        let alice = try #require(contacts.saved(at: ContactsFixtures.alice))
        let savings = try #require(contacts.saved(at: ContactsFixtures.savings))

        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        bruno.name = "Zed"
        contacts.save(bruno)
        contacts.delete(alice)
        contacts[isFavorite: bruno] = true
        contacts[isFavorite: savings] = false
        await contacts.load()

        let relaunched = await ContactsFixtures.model(store: ContactsFixtures.store(addressBook))
        #expect(relaunched.contacts.map(\.name) == ["Aaron", "Zed"])
        #expect(relaunched.favorites.map(\.name) == ["Zed"])
    }

    /// Windows share one store, so a change in one window shows in another at once, before it's saved.
    @Test func `Changes show in every window at once`() async throws {
        let store = ContactsFixtures.store()
        let window = await ContactsFixtures.model(store: store)
        let other = await ContactsFixtures.model(store: store)
        let alice = try #require(window.saved(at: ContactsFixtures.alice))

        window.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        window.delete(alice)

        #expect(other.contacts.map(\.name) == ["Aaron", "bruno"])
        await window.load()
    }

    /// A payment that lands shows under Recents in every window, from the shared transactions' record of it.
    @Test func `A landed payment shows in every window`() async throws {
        let sent = try PendingPayment(from: ContactsFixtures.main.id, to: ContactsFixtures.stranger)
        async let window = ContactsFixtures.model(transactions: sent.transactions, network: .devnet)
        async let other = ContactsFixtures.model(transactions: sent.transactions, network: .devnet)
        let (first, second) = await (window, other)
        #expect(first.recents.isEmpty)

        #expect(try await sent.settle() == .succeeded)

        #expect(first.recents.map(\.address) == [ContactsFixtures.stranger])
        #expect(second.recents.map(\.address) == [ContactsFixtures.stranger])
    }

    /// Recents list the latest payment to each address from every account in the wallet on the window's network.
    @Test func `Recents list the wallet's payments on the window's network`() async throws {
        let transactions = ContactsFixtures.transactions([
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .mainnet):
                StoredValue(ContactsFixtures.records),
            TransactionRecord.Key(account: ContactsFixtures.savingsAccount.id, network: .mainnet): StoredValue([
                .fixture(.payment(recipient: ContactsFixtures.recent, mint: nil, units: 1), signature: "savings",
                         account: ContactsFixtures.savingsAccount.id, network: .mainnet, status: .succeeded,
                         settled: 3_000),
            ]),
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .devnet):
                StoredValue([ContactsFixtures.payment(to: ContactsFixtures.stranger, signature: "devnet",
                                                      network: .devnet, settled: 4_000)]),
        ])

        async let mainnetModel = ContactsFixtures.model(transactions: transactions)
        async let devnetModel = ContactsFixtures.model(transactions: transactions, network: .devnet)
        let (mainnet, devnet) = await (mainnetModel, devnetModel)

        #expect(mainnet.payments.map(\.address) == [ContactsFixtures.recent, ContactsFixtures.alice])
        #expect(mainnet.payments.first?.date == Date(timeIntervalSinceReferenceDate: 3_000))
        #expect(devnet.payments.map(\.address) == [ContactsFixtures.stranger])
    }

    /// Only the latest payments are listed, so Recents stays short.
    @Test func `Only the latest ten payments are listed`() async throws {
        let addresses = try (1...12).map { try Address(bytes: [UInt8](repeating: UInt8($0), count: 32)) }
        let records = addresses.enumerated().map { index, address in
            ContactsFixtures.payment(to: address, signature: "payment-\(index)", settled: Double(index + 1))
        }
        let transactions = ContactsFixtures.transactions([
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .mainnet): StoredValue(records),
        ])

        let contacts = await ContactsFixtures.model(transactions: transactions)

        #expect(contacts.payments.map(\.address) == Array(addresses.reversed().prefix(ContactsModel.recentLimit)))
    }

    /// Storage that can't be read is reported instead of showing an empty list, and nothing replaces it.
    @Test func `Unreadable contacts are reported, not emptied`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook, unreadable: true)
        let contacts = await ContactsFixtures.model(store: ContactsFixtures.store(addressBook))

        #expect(contacts.isUnreadable)
        #expect(!contacts.isLoaded)
        #expect(await addressBook.value == ContactsFixtures.addressBook)
    }

    /// Recent payments that can't be read are reported, as unreadable contacts are.
    @Test func `Unreadable payments are reported`() async {
        let transactions = ContactsFixtures.transactions([
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .mainnet):
                StoredValue(ContactsFixtures.records, unreadable: true),
        ])
        let contacts = await ContactsFixtures.model(transactions: transactions)

        #expect(contacts.isUnreadable)
        #expect(!contacts.isLoaded)
    }

    /// Loading again after the contacts couldn't be read shows them once they can be.
    @Test func `Trying again reads unreadable contacts`() async throws {
        let addressBook = StoredValue(ContactsFixtures.addressBook, unreadable: true)
        let contacts = await ContactsFixtures.model(store: ContactsFixtures.store(addressBook))
        try #require(contacts.isUnreadable)
        // A save replaces the unreadable bytes, as a repaired file would.
        try await addressBook.save(ContactsFixtures.addressBook)

        await contacts.load()

        #expect(contacts.isLoaded)
        #expect(contacts.contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// A change that can't be saved shows an error, and the list returns to what's saved.
    @Test func `A change that can't be saved is undone`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook, failsSaving: true)
        let contacts = await ContactsFixtures.model(store: ContactsFixtures.store(addressBook))

        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        #expect(contacts.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
        await contacts.load()

        #expect(await firstError(of: contacts) == .unsaved)
        #expect(contacts.contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// Waits until a change that couldn't be saved sets the model's error.
    /// - Parameter contacts: The model that made the change.
    /// - Returns: The error, or `nil` if the test ends first.
    private func firstError(of contacts: ContactsModel) async -> ContactsError? {
        for await error in Observations({ contacts.error }) where error != nil { return error }
        return nil
    }
}
