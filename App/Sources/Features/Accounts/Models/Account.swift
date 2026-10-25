import Foundation
import Transactions
import Wallet

/// A local wallet identity without recovery material or signing keys.
nonisolated struct Account: Sendable, Equatable, Identifiable {
    /// The stable identity of this account.
    let id: UUID
    /// The protected recovery record shared by accounts from the same seed.
    let recoveryID: UUID
    /// The address derived from the shared recovery and this account's exact path.
    let address: Address
    /// The validated hardened path needed to recover this account's signing key.
    let path: DerivationPath
    /// The name the person gave the account, or `nil` while it keeps its ``defaultName``.
    var customName: String?

    /// Selects an existing wallet without reading protected recovery.
    /// - Parameters:
    ///   - id: The account's retained identity.
    ///   - recoveryID: The shared recovery identifier.
    ///   - address: The previously derived address; signing verifies this binding again.
    ///   - path: The exact derivation path paired with the address.
    ///   - customName: The name the person gave the account, or `nil` for its ``defaultName``.
    init(id: UUID, recoveryID: UUID, address: Address, path: DerivationPath, customName: String? = nil) {
        self.id = id
        self.recoveryID = recoveryID
        self.address = address
        self.path = path
        self.customName = customName
    }

    /// Keeps a newly derived account of a wallet under a new identity, with no name of its own.
    /// - Parameters:
    ///   - derived: The derived address and its path.
    ///   - recoveryID: The wallet's recovery identifier.
    /// - Throws: An address validation error.
    init(_ derived: DerivedAccount, recoveryID: UUID) throws {
        self.init(id: UUID(), recoveryID: recoveryID, address: try Address(derived.address), path: derived.path)
    }

    /// The account's name: the one the person gave it, or its ``defaultName``.
    var name: String { customName ?? defaultName }

    /// The account's name before the person names it, numbered from 1 by its account index as Phantom does, such as
    /// Account 2 for `m/44'/501'/1'/0'`, or its path when the path is outside the Solana account families.
    var defaultName: String {
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
