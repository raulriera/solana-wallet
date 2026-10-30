import Foundation
import Transactions
import Wallet

/// An address of a saved wallet, without recovery material or signing keys.
nonisolated struct Account: Sendable, Hashable, Identifiable {
    let id: UUID
    let recoveryID: UUID
    let address: Address
    let path: DerivationPath
    /// The name the person gave the account, or `nil` for its ``defaultName``.
    var customName: String?

    /// Creates an account.
    ///
    /// - Parameters:
    ///   - id: The account's identifier.
    ///   - recoveryID: The identifier of the wallet's recovery.
    ///   - address: The account's address.
    ///   - path: The derivation path of the address.
    ///   - customName: The name the person gave the account, or `nil` for its ``defaultName``.
    init(id: UUID, recoveryID: UUID, address: Address, path: DerivationPath, customName: String? = nil) {
        self.id = id
        self.recoveryID = recoveryID
        self.address = address
        self.path = path
        self.customName = customName
    }

    /// Creates an account with a new identifier and no custom name from a derived account.
    ///
    /// - Parameters:
    ///   - derived: The derived address and its path.
    ///   - recoveryID: The identifier of the wallet's recovery.
    /// - Throws: An address validation error.
    init(_ derived: DerivedAccount, recoveryID: UUID) throws {
        self.init(id: UUID(), recoveryID: recoveryID, address: try Address(derived.address), path: derived.path)
    }

    /// The ``customName``, or the ``defaultName`` when there is none.
    var name: String { customName ?? defaultName }

    /// The name numbered from 1 by account index, such as Account 2 for `m/44'/501'/1'/0'`, or else the path.
    var defaultName: String {
        guard let index = path.accountIndex else { return path.description }
        return String(localized: "Account \(Int(index) + 1)", comment: "A wallet account's name, numbered from 1.")
    }

    /// Returns whether an account duplicates this one.
    ///
    /// - Parameter other: The account to compare.
    /// - Returns: `true` when the accounts share an identifier, an address, or a recovery and path.
    func isDuplicate(of other: Account) -> Bool {
        id == other.id || address == other.address || (recoveryID == other.recoveryID && path == other.path)
    }
}
