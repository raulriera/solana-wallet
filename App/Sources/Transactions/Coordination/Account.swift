import Foundation
import Transactions
import Wallet

/// A local wallet identity without recovery material or signing keys.
nonisolated struct Account: Sendable {
    /// The stable identity of this account.
    let id: UUID
    /// The protected recovery record shared by accounts from the same seed.
    let recoveryID: UUID
    /// The address derived from the shared recovery and this account's index.
    let address: Address
    /// The account number within the app's fixed Solana derivation pattern.
    let index: UInt32

    /// The hardened path constructed from the account number.
    /// - Throws: `DerivationPath.ValidationError.invalidPath` if the index is at least 2³¹.
    var path: DerivationPath {
        get throws { try DerivationPath("m/44'/501'/\(index)'/0'") }
    }

    /// Selects an existing wallet without reading protected recovery.
    /// - Parameters:
    ///   - id: The account's retained identity.
    ///   - recoveryID: The shared recovery identifier.
    ///   - address: The previously derived address; signing verifies this binding again.
    ///   - index: The account number, starting at zero for the first address.
    init(id: UUID, recoveryID: UUID, address: Address, index: UInt32) {
        self.id = id
        self.recoveryID = recoveryID
        self.address = address
        self.index = index
    }
}
