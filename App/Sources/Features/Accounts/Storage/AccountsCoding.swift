import Foundation
import Storage
import Transactions
import Wallet

/// Keeps the saved accounts as a JSON list of their public fields, and reads back only a list of valid, distinct
/// accounts.
///
/// A list with an invalid address or path, a missing field, or a duplicate account isn't a value, so a file that keeps
/// one is unreadable and is never replaced.
nonisolated struct AccountsCoding: ValueCoding {
    /// Creates a coding that keeps accounts as JSON.
    init() {}

    /// Converts the accounts to the JSON list of their public fields.
    /// - Parameter accounts: The accounts to save.
    /// - Returns: The accounts' JSON.
    /// - Throws: An encoding error if the accounts can't be represented as JSON.
    func encode(_ accounts: [Account]) throws -> Data {
        try JSONEncoder().encode(accounts.map(Record.init))
    }

    /// Converts the JSON list back to accounts, checking each address and path and that no account is saved twice.
    /// - Parameter data: The kept JSON.
    /// - Returns: The accounts, or `nil` when the bytes aren't a list of valid, distinct accounts.
    func decode(_ data: Data) -> [Account]? {
        guard let records = try? JSONDecoder().decode([Record].self, from: data),
              let accounts = try? records.map({ try $0.account() }),
              accounts.indices.allSatisfy({ index in
                  !accounts[..<index].contains { $0.isDuplicate(of: accounts[index]) }
              }) else { return nil }
        return accounts
    }

    /// The public fields saved for each account; recovery secrets have no representation here.
    private struct Record: Codable {
        let id: UUID
        let recoveryID: UUID
        let address: String
        let path: String

        /// Copies an account's public fields into its saved representation.
        /// - Parameter account: The account to save.
        init(_ account: Account) {
            id = account.id
            recoveryID = account.recoveryID
            address = account.address.value
            path = account.path.description
        }

        /// Reconstructs the account, checking its address and path.
        /// - Returns: The account.
        /// - Throws: An address or derivation-path validation error.
        func account() throws -> Account {
            Account(id: id, recoveryID: recoveryID, address: try Address(address), path: try DerivationPath(path))
        }
    }
}

extension ValueCoding where Self == AccountsCoding {
    /// Keeps the saved accounts as a JSON list of their public fields.
    nonisolated static var accounts: AccountsCoding { AccountsCoding() }
}
