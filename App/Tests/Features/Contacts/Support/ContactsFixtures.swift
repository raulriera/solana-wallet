import Foundation
import RPC
import Storage
import Transactions
import Wallet
@testable import widgets

// swift-format-ignore: NeverForceUnwrap, NeverUseForceTry
/// Addresses and a contacts list for the contacts tests, generated for them and owned by no one.
nonisolated enum ContactsFixtures {
    /// The account payments leave from.
    static let sending = try! Address("7ojbqZyHTdFHMo5WAJyttWEHwtwfStdkAMh8fme8wNFs")
    /// Another account of the wallet.
    static let savings = try! Address("A7Csd6PpFzYtvF17bdxASoLTPZ1xxyeLudQgpKVYPTw1")
    /// A favorite contact who was paid.
    static let alice = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    /// Differs from ``alice`` only in the middle.
    static let aliceLookAlike = try! Address("6d8tEyrqPq1bEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    /// A contact who was never paid.
    static let bruno = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")
    /// An address with no key, as programs derive.
    static let program = try! Address("EXKmNaFvM61XU4RHuh8moR67QArXabU4NzW5yyPfyBK9")
    /// An unsaved address that was never paid.
    static let stranger = try! Address("5Wqz5yrwY2mGG9qqD9MUU7QYehEkv8kcdQgMKhV7wXaV")
    /// An unsaved address that was paid.
    static let recent = try! Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV")

    /// The wallet whose accounts' payments are listed.
    static let wallet = UUID(uuidString: "0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90")!
    /// The saved account payments leave from, named Main.
    static let main = widgets.Account(id: UUID(uuidString: "6F1C2B3A-4D5E-4F60-8A7B-9C0D1E2F3A4B")!,
                                      recoveryID: wallet, address: sending, path: .solana, customName: "Main")
    /// The wallet's other saved account, named Savings.
    static let savingsAccount = widgets.Account(id: UUID(uuidString: "1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9")!,
                                                recoveryID: wallet, address: savings,
                                                path: try! DerivationPath("m/44'/501'/1'/0'"), customName: "Savings")

    /// Saved contacts Alice, a favorite, and bruno, with the Savings account as a favorite.
    static let addressBook: AddressBook = {
        var book = AddressBook()
        book.save(Contact(name: "bruno", address: bruno))
        book.save(Contact(name: "Alice", address: alice, isFavorite: true))
        book.setFavorite(true, forAccountAt: savings)
        return book
    }()

    /// The sending account's succeeded payments on mainnet to an unsaved address, then to Alice.
    @MainActor
    static var records: [TransactionRecord] {
        [payment(to: alice, signature: "alice", settled: 2_000), payment(to: recent, signature: "recent", settled: 1_000)]
    }

    /// A succeeded payment from one of the wallet's accounts.
    /// - Parameters:
    ///   - recipient: Who the payment went to.
    ///   - signature: The payment's signature.
    ///   - account: The identifier of the account that paid, the sending account's by default.
    ///   - network: The network it was sent on.
    ///   - settled: When it landed, in seconds after 1 January 2001.
    /// - Returns: The payment's record.
    @MainActor
    static func payment(to recipient: Address, signature: String, account: UUID = main.id, network: Network = .mainnet,
                        settled: TimeInterval) -> TransactionRecord {
        .fixture(.payment(recipient: recipient, mint: nil, units: 1), signature: signature, account: account,
                 network: network, status: .succeeded, created: settled - 1, settled: settled)
    }

    /// A contact store over storage that keeps the address book in memory, starting with ``addressBook``.
    /// - Parameter addressBook: The saved contacts and favorites.
    /// - Returns: A contact store that hasn't read the storage yet.
    @MainActor
    static func store(_ addressBook: StoredValue<AddressBook> = StoredValue(addressBook)) -> ContactStore {
        ContactStore(storage: addressBook)
    }

    /// Shared transactions over in-memory records, whose coordinators never leave the process.
    /// - Parameter records: Each key's records; by default the sending account's mainnet records are ``records``.
    /// - Returns: Transactions that haven't read the records yet.
    @MainActor
    static func transactions(_ records: [TransactionRecord.Key: StoredValue<[TransactionRecord]>] = [
        TransactionRecord.Key(account: main.id, network: .mainnet): StoredValue(Self.records),
    ]) -> TransactionStore {
        .inMemory(records)
    }

    /// The lists of the sending account, as read from ``addressBook`` and its payments to Alice and an unsaved
    /// address: a favorite other account, two contacts, and one recent payment.
    static let lists = ContactLists(sendingAccount: sending, accounts: [Contact(savingsAccount)], addressBook: addressBook,
                                    payments: [RecentPayment(address: alice, date: Date(timeIntervalSinceReferenceDate: 2_000)),
                                               RecentPayment(address: recent, date: Date(timeIntervalSinceReferenceDate: 1_000))],
                                    keys: [], phase: .loaded)

    /// A tab's contacts for the sending account in a wallet with the Savings account, read from storage.
    /// - Parameters:
    ///   - store: The contacts to read, ``store(_:)`` by default.
    ///   - transactions: The records to read, ``transactions(_:)`` by default.
    ///   - network: The network whose recent payments are listed.
    /// - Returns: The loaded tab.
    @MainActor
    static func tab(store: ContactStore? = nil, transactions: TransactionStore? = nil,
                    network: Network = .mainnet) async -> ContactsTab {
        let tab = ContactsTab(store: store ?? self.store(), transactions: transactions ?? self.transactions(),
                              network: network)
        await tab.load()
        return tab
    }
}

/// One Contacts tab over shared stores, which reads its lists as the tab's split view does.
@MainActor
struct ContactsTab {
    /// The tab's changes to contacts and favorites.
    let model = ContactsModel()
    /// The saved contacts and favorites that every window shares.
    let store: ContactStore
    /// The transactions that every window sends, watches, and records.
    let transactions: TransactionStore
    /// The network whose recent payments are listed.
    let network: Network
    /// The wallet's accounts, in wallet order; the first pays.
    var wallet = [ContactsFixtures.main, ContactsFixtures.savingsAccount]

    /// The lists the tab shows now.
    var lists: ContactLists {
        model.lists(for: ContactsFixtures.main, on: network, in: wallet, store: store, transactions: transactions)
    }

    /// Reads the saved contacts and the listed records.
    func load() async {
        await model.load(lists.keys, from: store, transactions: transactions)
    }
}
