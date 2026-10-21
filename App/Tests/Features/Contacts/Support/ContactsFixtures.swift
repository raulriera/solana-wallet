import Foundation
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
    /// A contact who was never paid.
    static let bruno = try! Address("F3sVqBYJWSBdbsMtZes3AEKkBaiHHokhENFWA1PoMFSf")
    /// An unsaved address that was paid.
    static let recent = try! Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV")

    /// A list with the sending account, a favorite other account, two contacts, and payments to Alice and an
    /// unsaved address.
    /// - Returns: The contacts model.
    @MainActor
    static func model() -> ContactsModel {
        ContactsModel(
            sendingAccount: sending,
            accounts: [Contact(name: "Main", address: sending), Contact(name: "Savings", address: savings,
                                                                         isFavorite: true)],
            contacts: [Contact(name: "bruno", address: bruno), Contact(name: "Alice", address: alice,
                                                                         isFavorite: true)],
            payments: [RecentPayment(address: recent, date: Date(timeIntervalSince1970: 1_000)),
                       RecentPayment(address: alice, date: Date(timeIntervalSince1970: 2_000))])
    }
}
