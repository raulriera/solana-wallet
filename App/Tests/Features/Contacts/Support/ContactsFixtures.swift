import Foundation
import RPC
import Storage
import Transactions
import Wallet
@testable import widgets

// swift-format-ignore: NeverForceUnwrap, NeverUseForceTry
nonisolated enum ContactsFixtures {
    static let sending = try! Address("7ojbqZyHTdFHMo5WAJyttWEHwtwfStdkAMh8fme8wNFs")
    static let savings = try! Address("A7Csd6PpFzYtvF17bdxASoLTPZ1xxyeLudQgpKVYPTw1")
    static let alice = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    static let aliceLookAlike = try! Address("6d8tEyrqPq1bEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    static let bruno = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")
    static let program = try! Address("EXKmNaFvM61XU4RHuh8moR67QArXabU4NzW5yyPfyBK9")
    static let stranger = try! Address("5Wqz5yrwY2mGG9qqD9MUU7QYehEkv8kcdQgMKhV7wXaV")
    static let recent = try! Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV")

    static let wallet = UUID(uuidString: "0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90")!
    static let main = widgets.Account(id: UUID(uuidString: "6F1C2B3A-4D5E-4F60-8A7B-9C0D1E2F3A4B")!,
                                      recoveryID: wallet, address: sending, path: .solana, customName: "Main")
    static let savingsAccount = widgets.Account(id: UUID(uuidString: "1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9")!,
                                                recoveryID: wallet, address: savings,
                                                path: try! DerivationPath("m/44'/501'/1'/0'"), customName: "Savings")

    static let addressBook: AddressBook = {
        var book = AddressBook()
        book.save(Contact(name: "bruno", address: bruno))
        book.save(Contact(name: "Alice", address: alice, isFavorite: true))
        book.setFavorite(true, forAccountAt: savings)
        return book
    }()

    @MainActor
    static var records: [TransactionRecord] {
        [payment(to: alice, signature: "alice", settled: 2_000), payment(to: recent, signature: "recent", settled: 1_000)]
    }

    @MainActor
    static func payment(to recipient: Address, signature: String, account: UUID = main.id, network: Network = .mainnet,
                        settled: TimeInterval) -> TransactionRecord {
        .fixture(.payment(recipient: recipient, mint: nil, units: 1), signature: signature, account: account,
                 network: network, status: .succeeded, created: settled - 1, settled: settled)
    }

    @MainActor
    static func store(_ addressBook: StoredValue<AddressBook> = StoredValue(addressBook)) -> ContactStore {
        ContactStore(storage: addressBook)
    }

    @MainActor
    static func transactions(_ records: [TransactionRecord.Key: StoredValue<[TransactionRecord]>] = [
        TransactionRecord.Key(account: main.id, network: .mainnet): StoredValue(Self.records),
    ]) -> TransactionStore {
        .inMemory(records)
    }

    static let lists = ContactLists(sendingAccount: sending, accounts: [Contact(savingsAccount)], addressBook: addressBook,
                                    payments: [RecentPayment(address: alice, date: Date(timeIntervalSinceReferenceDate: 2_000)),
                                               RecentPayment(address: recent, date: Date(timeIntervalSinceReferenceDate: 1_000))],
                                    keys: [], phase: .loaded)

    @MainActor
    static func tab(store: ContactStore? = nil, transactions: TransactionStore? = nil,
                    network: Network = .mainnet) async -> ContactsTab {
        let tab = ContactsTab(store: store ?? self.store(), transactions: transactions ?? self.transactions(),
                              network: network)
        await tab.load()
        return tab
    }
}

@MainActor
struct ContactsTab {
    let model = ContactsModel()
    let store: ContactStore
    let transactions: TransactionStore
    let network: Network
    var wallet = [ContactsFixtures.main, ContactsFixtures.savingsAccount]

    var lists: ContactLists {
        model.lists(for: ContactsFixtures.main, on: network, in: wallet, store: store, transactions: transactions)
    }

    func load() async {
        await model.load(lists.keys, from: store, transactions: transactions)
    }
}
