import Foundation
import Transactions
import Wallet

/// A local wallet identity without recovery material or signing keys.
nonisolated struct Account: Sendable {
    /// The stable identity of this account.
    let id: UUID
    /// The protected recovery record shared by accounts from the same seed.
    let recoveryID: UUID
    /// The address derived from the shared recovery and this account's exact path.
    let address: Address
    /// The validated hardened path needed to recover this account's signing key.
    let path: DerivationPath

    /// Selects an existing wallet without reading protected recovery.
    /// - Parameters:
    ///   - id: The account's retained identity.
    ///   - recoveryID: The shared recovery identifier.
    ///   - address: The previously derived address; signing verifies this binding again.
    ///   - path: The exact derivation path paired with the address.
    init(id: UUID, recoveryID: UUID, address: Address, path: DerivationPath) {
        self.id = id
        self.recoveryID = recoveryID
        self.address = address
        self.path = path
    }
}
