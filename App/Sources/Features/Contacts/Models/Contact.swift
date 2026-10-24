import Foundation
import Transactions

/// An address saved under a name: a contact, or one of the wallet's own accounts.
nonisolated struct Contact: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// The name that labels the address.
    var name: String
    /// The address the name labels.
    var address: Address
    /// Whether the address also shows under Favorites.
    var isFavorite: Bool

    /// Creates a named address.
    /// - Parameters:
    ///   - id: The contact's identity, which stays when its name or address changes.
    ///   - name: The name that labels the address.
    ///   - address: The address the name labels.
    ///   - isFavorite: Whether the address also shows under Favorites.
    init(id: UUID = UUID(), name: String, address: Address, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.isFavorite = isFavorite
    }
}
