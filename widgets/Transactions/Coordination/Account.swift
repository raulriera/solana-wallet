import Foundation
import Transactions

/// A local wallet identity without recovery material or signing keys.
nonisolated struct Account: Sendable {
    /// The identifier of the wallet's protected recovery record.
    let id: UUID
    /// The address derived from that record's phrase, passphrase, and derivation path.
    let address: Address

    /// Selects an existing wallet without reading protected recovery.
    /// - Parameters:
    ///   - id: The retained recovery identifier.
    ///   - address: The previously derived address; signing verifies this binding again.
    init(id: UUID, address: Address) {
        self.id = id
        self.address = address
    }
}
