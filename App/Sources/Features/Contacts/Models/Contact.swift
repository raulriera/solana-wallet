import Foundation
import Transactions

/// An address saved under a name: a contact, or one of the wallet's own accounts.
nonisolated struct Contact: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var address: Address
    /// Whether the address shows under Favorites.
    var isFavorite: Bool

    /// The address as a payment's recipient, under the contact's name.
    var recipient: PaymentRecipient { PaymentRecipient(address: address, name: name) }

    /// Creates a named address.
    ///
    /// - Parameters:
    ///   - id: The contact's identifier.
    ///   - name: The name that labels the address.
    ///   - address: The address the name labels.
    ///   - isFavorite: Whether the address shows under Favorites.
    init(id: UUID = UUID(), name: String, address: Address, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.isFavorite = isFavorite
    }

    /// Creates a contact with an account's identifier, name, and address.
    ///
    /// - Parameter account: The account.
    init(_ account: Account) {
        self.init(id: account.id, name: account.name, address: account.address)
    }
}
