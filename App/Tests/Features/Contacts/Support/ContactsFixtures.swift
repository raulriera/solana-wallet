import Foundation
import RPC
import Storage
import Transactions
@testable import widgets

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

    /// The wallet whose recent payments are listed.
    static let wallet = UUID(uuidString: "0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90")!

    /// Saved contacts Alice, a favorite, and bruno, with the Savings account as a favorite.
    static let addressBook: AddressBook = {
        var book = AddressBook()
        book.save(Contact(name: "bruno", address: bruno))
        book.save(Contact(name: "Alice", address: alice, isFavorite: true))
        book.setFavorite(true, forAccountAt: savings)
        return book
    }()

    /// The wallet's payments on mainnet to Alice and an unsaved address.
    static var recents: [String: [RecentPayment]] {
        [ContactsModel.recentsKey(wallet: wallet, network: .mainnet): [
            RecentPayment(address: recent, date: Date(timeIntervalSince1970: 1_000)),
            RecentPayment(address: alice, date: Date(timeIntervalSince1970: 2_000)),
        ]]
    }

    /// A contact store over storage that keeps the address book in memory, starting with ``addressBook``.
    /// - Parameter addressBook: The saved contacts and favorites.
    /// - Returns: A contact store that hasn't read the storage yet.
    @MainActor
    static func store(_ addressBook: StoredValue<AddressBook> = StoredValue(addressBook)) -> ContactStore {
        ContactStore(storage: addressBook)
    }

    /// Contacts services over storage that keeps recent payments in memory, starting with ``recents``.
    /// - Parameter recents: The saved recent payments.
    /// - Returns: Contacts services that haven't read the storage yet.
    @MainActor
    static func services(recents: StoredValue<[String: [RecentPayment]]> = StoredValue(recents)) -> ContactsServices {
        ContactsServices(storage: recents)
    }

    /// A list with the sending account, a favorite other account, two contacts, and payments to Alice and an
    /// unsaved address, read from storage.
    /// - Parameters:
    ///   - store: The contacts to read, ``store(_:)`` by default.
    ///   - services: The recent payments to read, ``services(recents:)`` by default.
    ///   - network: The network whose recent payments are listed.
    /// - Returns: The loaded contacts model.
    @MainActor
    static func model(store: ContactStore? = nil, services: ContactsServices? = nil,
                      network: Network = .mainnet) async -> ContactsModel {
        let model = ContactsModel(sendingAccount: sending, wallet: wallet, network: network,
                                  accounts: [Contact(name: "Main", address: sending),
                                             Contact(name: "Savings", address: savings)],
                                  store: store ?? self.store(), services: services ?? self.services())
        await model.load()
        return model
    }
}
