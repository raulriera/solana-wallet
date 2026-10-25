import Foundation
import Transactions
import Wallet

/// A local wallet identity without recovery material or signing keys.
nonisolated struct Account: Sendable, Equatable {
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

    /// The account's name, numbered from 1 by its account index as Phantom does, such as Account 2 for
    /// `m/44'/501'/1'/0'`, or its path when the path is outside the Solana account families.
    var name: String {
        guard let index = path.accountIndex else { return path.description }
        return String(localized: "Account \(Int(index) + 1)", comment: "A wallet account's name, numbered from 1.")
    }

    /// Whether another account can't be saved beside this one: it has the same identity or address, or the same
    /// recovery and path.
    /// - Parameter other: Another account.
    /// - Returns: `true` when the accounts share an identity, an address, or a recovery and path.
    func isDuplicate(of other: Account) -> Bool {
        id == other.id || address == other.address || (recoveryID == other.recoveryID && path == other.path)
    }
}
