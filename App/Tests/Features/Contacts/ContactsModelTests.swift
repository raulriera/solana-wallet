import Foundation
import Observation
import RPC
import Storage
import Testing
import Wallet
@testable import Transactions
@testable import widgets

/// Checks how the contacts model reads an account's lists on a network, and how it saves, favorites, and deletes.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactsModelTests {
    /// The lists are read from the stores and never offer the sending account.
    @Test func `Lists are read without the sending account`() async {
        let lists = await ContactsFixtures.tab().lists
        #expect(lists.isLoaded)
        #expect(lists.accounts.map(\.address) == [ContactsFixtures.savings])
        #expect(!lists.lists(ContactsFixtures.sending))
    }

    /// Payments are kept newest first.
    @Test func `Payments are newest first`() async {
        #expect(await ContactsFixtures.tab().lists.payments.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// A new contact joins the list in name order.
    @Test func `Saving a new contact keeps the list sorted`() async {
        let tab = await ContactsFixtures.tab()
        tab.model.save(Contact(name: "Aaron", address: ContactsFixtures.stranger), in: tab.store)
        #expect(tab.lists.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
    }

    /// Saving a contact with an existing identity replaces it instead of adding another.
    @Test func `Saving an edited contact replaces it`() async throws {
        let tab = await ContactsFixtures.tab()
        var bruno = try #require(tab.lists.saved(at: ContactsFixtures.bruno))
        bruno.name = "Zed"
        tab.model.save(bruno, in: tab.store)
        #expect(tab.lists.contacts.map(\.name) == ["Alice", "Zed"])
    }

    /// Deleting a contact who was paid lists their address under Recents again.
    @Test func `Deleting a paid contact returns them to Recents`() async throws {
        let tab = await ContactsFixtures.tab()
        tab.model.delete(try #require(tab.lists.saved(at: ContactsFixtures.alice)), from: tab.store)
        #expect(tab.lists.contacts.map(\.address) == [ContactsFixtures.bruno])
        #expect(tab.lists.recents.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Accounts and contacts both join and leave Favorites.
    @Test func `Favorites toggle for accounts and contacts`() async throws {
        let tab = await ContactsFixtures.tab()
        let savings = try #require(tab.lists.saved(at: ContactsFixtures.savings))
        let bruno = try #require(tab.lists.saved(at: ContactsFixtures.bruno))
        tab.model.setFavorite(false, for: savings, in: tab.lists, store: tab.store)
        tab.model.setFavorite(true, for: bruno, in: tab.lists, store: tab.store)
        #expect(tab.lists.favorites.map(\.name) == ["Alice", "bruno"])
    }

    /// An address the lists don't save, such as a recent payment's, can't become a favorite.
    @Test func `An unsaved address can't become a favorite`() async {
        let tab = await ContactsFixtures.tab()
        tab.model.setFavorite(true, for: Contact(name: "Recent", address: ContactsFixtures.recent), in: tab.lists,
                              store: tab.store)
        await tab.load()
        #expect(tab.lists.favorites.map(\.name) == ["Savings", "Alice"])
        #expect(tab.store.addressBook == ContactsFixtures.addressBook)
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
        var tab = ContactsTab(store: ContactsFixtures.store(addressBook), transactions: .unused, network: .mainnet)
        tab.wallet = accounts.accounts(inWallet: ContactsFixtures.wallet)
        await tab.load()

        let listed = try #require(tab.lists.accounts.first)
        #expect(tab.lists.accounts.count == 1)
        #expect(listed.id == savings.id)
        #expect(listed.address == ContactsFixtures.savings)
        #expect(listed.name == "Account 2")

        tab.model.setFavorite(true, for: listed, in: tab.lists, store: tab.store)
        await tab.load()

        #expect(tab.lists.favorites.map(\.address) == [ContactsFixtures.savings])
        #expect(await addressBook.value?.favoriteAccounts == [ContactsFixtures.savings])
    }

    /// An account added to the wallet is listed at once, and its payments are read with the others'.
    @Test func `A new account in the wallet is listed at once`() async {
        let added = widgets.Account(id: UUID(), recoveryID: ContactsFixtures.wallet, address: ContactsFixtures.stranger,
                                    path: .solana(account: 2), customName: "Travel")
        let transactions = ContactsFixtures.transactions([
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .mainnet): StoredValue(ContactsFixtures.records),
            TransactionRecord.Key(account: added.id, network: .mainnet): StoredValue([
                ContactsFixtures.payment(to: ContactsFixtures.bruno, signature: "travel", account: added.id,
                                         settled: 3_000),
            ]),
        ])
        var tab = await ContactsFixtures.tab(transactions: transactions)

        tab.wallet.append(added)

        #expect(tab.lists.accounts.map(\.name) == ["Savings", "Travel"])
        #expect(!tab.lists.isLoaded)
        await tab.load()
        #expect(tab.lists.isLoaded)
        #expect(tab.lists.payments.map(\.address) == [ContactsFixtures.bruno, ContactsFixtures.alice,
                                                       ContactsFixtures.recent])
    }

    /// A wallet with only its sending account and no contacts or payments has no one to list.
    @Test func `A list without anyone else is empty`() async {
        var tab = ContactsTab(store: ContactsFixtures.store(StoredValue()), transactions: .unused, network: .mainnet)
        tab.wallet = [ContactsFixtures.main]

        await tab.load()

        #expect(tab.lists.isLoaded)
        #expect(tab.lists.isEmpty)
    }

    /// New, edited, deleted, and favorite contacts and favorite accounts are read back by the next list, as after a
    /// relaunch.
    @Test func `Changes are saved for the next list`() async throws {
        let addressBook = StoredValue(ContactsFixtures.addressBook)
        let tab = await ContactsFixtures.tab(store: ContactsFixtures.store(addressBook))
        var bruno = try #require(tab.lists.saved(at: ContactsFixtures.bruno))
        let alice = try #require(tab.lists.saved(at: ContactsFixtures.alice))
        let savings = try #require(tab.lists.saved(at: ContactsFixtures.savings))

        tab.model.save(Contact(name: "Aaron", address: ContactsFixtures.stranger), in: tab.store)
        bruno.name = "Zed"
        tab.model.save(bruno, in: tab.store)
        tab.model.delete(alice, from: tab.store)
        tab.model.setFavorite(true, for: bruno, in: tab.lists, store: tab.store)
        tab.model.setFavorite(false, for: savings, in: tab.lists, store: tab.store)
        await tab.load()

        let relaunched = await ContactsFixtures.tab(store: ContactsFixtures.store(addressBook))
        #expect(relaunched.lists.contacts.map(\.name) == ["Aaron", "Zed"])
        #expect(relaunched.lists.favorites.map(\.name) == ["Zed"])
    }

    /// Windows share one store, so a change in one window shows in another at once, before it's saved.
    @Test func `Changes show in every window at once`() async throws {
        let store = ContactsFixtures.store()
        let window = await ContactsFixtures.tab(store: store)
        let other = await ContactsFixtures.tab(store: store)
        let alice = try #require(window.lists.saved(at: ContactsFixtures.alice))

        window.model.save(Contact(name: "Aaron", address: ContactsFixtures.stranger), in: store)
        window.model.delete(alice, from: store)

        #expect(other.lists.contacts.map(\.name) == ["Aaron", "bruno"])
        await window.load()
    }

    /// A payment that lands shows under Recents in every window, from the shared transactions' record of it.
    @Test func `A landed payment shows in every window`() async throws {
        let sent = try PendingPayment(from: ContactsFixtures.main.id, to: ContactsFixtures.stranger)
        async let window = ContactsFixtures.tab(transactions: sent.transactions, network: .devnet)
        async let other = ContactsFixtures.tab(transactions: sent.transactions, network: .devnet)
        let (first, second) = await (window, other)
        #expect(first.lists.recents.isEmpty)

        #expect(try await sent.settle() == .succeeded)

        #expect(first.lists.recents.map(\.address) == [ContactsFixtures.stranger])
        #expect(second.lists.recents.map(\.address) == [ContactsFixtures.stranger])
    }

    /// Recents list the latest payment to each address from every account in the wallet on the tab's network.
    @Test func `Recents list the wallet's payments on the tab's network`() async throws {
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

        async let mainnetTab = ContactsFixtures.tab(transactions: transactions)
        async let devnetTab = ContactsFixtures.tab(transactions: transactions, network: .devnet)
        let (mainnet, devnet) = await (mainnetTab, devnetTab)

        #expect(mainnet.lists.payments.map(\.address) == [ContactsFixtures.recent, ContactsFixtures.alice])
        #expect(mainnet.lists.payments.first?.date == Date(timeIntervalSinceReferenceDate: 3_000))
        #expect(devnet.lists.payments.map(\.address) == [ContactsFixtures.stranger])
    }

    /// One model lists another network's payments when it's asked for that network, instead of the lists it derived
    /// before.
    @Test func `Another network gets its own lists`() async throws {
        let transactions = ContactsFixtures.transactions([
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .mainnet):
                StoredValue(ContactsFixtures.records),
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .devnet):
                StoredValue([ContactsFixtures.payment(to: ContactsFixtures.stranger, signature: "devnet",
                                                      network: .devnet, settled: 4_000)]),
        ])
        let tab = await ContactsFixtures.tab(transactions: transactions)
        let mainnetLists = tab.lists

        let unread = tab.model.lists(for: ContactsFixtures.main, on: .devnet, in: tab.wallet, store: tab.store,
                                     transactions: transactions)
        await tab.model.load(unread.keys, from: tab.store, transactions: transactions)
        let devnetLists = tab.model.lists(for: ContactsFixtures.main, on: .devnet, in: tab.wallet, store: tab.store,
                                          transactions: transactions)

        #expect(mainnetLists.payments.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
        #expect(devnetLists.keys.map(\.network) == [.devnet, .devnet])
        #expect(devnetLists.payments.map(\.address) == [ContactsFixtures.stranger])
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

        let tab = await ContactsFixtures.tab(transactions: transactions)

        #expect(tab.lists.payments.map(\.address) == Array(addresses.reversed().prefix(ContactsModel.recentLimit)))
    }

    /// Storage that can't be read is reported instead of showing an empty list, and nothing replaces it.
    @Test func `Unreadable contacts are reported, not emptied`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook, unreadable: true)
        let tab = await ContactsFixtures.tab(store: ContactsFixtures.store(addressBook))

        #expect(tab.lists.isUnreadable)
        #expect(!tab.lists.isLoaded)
        #expect(await addressBook.value == ContactsFixtures.addressBook)
    }

    /// Recent payments that can't be read are reported, as unreadable contacts are.
    @Test func `Unreadable payments are reported`() async {
        let transactions = ContactsFixtures.transactions([
            TransactionRecord.Key(account: ContactsFixtures.main.id, network: .mainnet):
                StoredValue(ContactsFixtures.records, unreadable: true),
        ])
        let tab = await ContactsFixtures.tab(transactions: transactions)

        #expect(tab.lists.isUnreadable)
        #expect(!tab.lists.isLoaded)
    }

    /// Loading again after the contacts couldn't be read shows them once they can be.
    @Test func `Trying again reads unreadable contacts`() async throws {
        let addressBook = StoredValue(ContactsFixtures.addressBook, unreadable: true)
        let tab = await ContactsFixtures.tab(store: ContactsFixtures.store(addressBook))
        try #require(tab.lists.isUnreadable)
        // A save replaces the unreadable bytes, as a repaired file would.
        try await addressBook.save(ContactsFixtures.addressBook)

        await tab.load()

        #expect(tab.lists.isLoaded)
        #expect(tab.lists.contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// A change that can't be saved shows an error, and the list returns to what's saved.
    @Test func `A change that can't be saved is undone`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook, failsSaving: true)
        let tab = await ContactsFixtures.tab(store: ContactsFixtures.store(addressBook))

        tab.model.save(Contact(name: "Aaron", address: ContactsFixtures.stranger), in: tab.store)
        #expect(tab.lists.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
        await tab.load()

        #expect(await firstError(of: tab.model) == .unsaved)
        #expect(tab.lists.contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// Waits until a change that couldn't be saved sets the model's error.
    /// - Parameter contacts: The model that made the change.
    /// - Returns: The error, or `nil` if the test ends first.
    private func firstError(of contacts: ContactsModel) async -> ContactsError? {
        for await error in Observations({ contacts.error }) where error != nil { return error }
        return nil
    }
}
