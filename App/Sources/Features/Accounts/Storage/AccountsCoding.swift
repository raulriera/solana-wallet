import Foundation
import Storage
import Transactions
import Wallet

/// A coding that keeps accounts as a JSON list of their public fields and reads back only valid, distinct accounts.
nonisolated struct AccountsCoding: ValueCoding {
    /// Creates a coding that keeps accounts as JSON.
    init() {}

    func encode(_ accounts: [Account]) throws -> Data {
        try JSONEncoder().encode(accounts.map(Record.init))
    }

    func decode(_ data: Data) -> [Account]? {
        guard let records = try? JSONDecoder().decode([Record].self, from: data),
              let accounts = try? records.map({ try $0.account() }),
              accounts.indices.allSatisfy({ index in
                  !accounts[..<index].contains { $0.isDuplicate(of: accounts[index]) }
              }) else { return nil }
        return accounts
    }

    /// The saved public fields of an account.
    private struct Record: Codable {
        let id: UUID
        let recoveryID: UUID
        let address: String
        let path: String
        /// The name the person gave the account, or `nil` for its numbered name.
        let name: String?

        /// Creates a record of an account's public fields.
        ///
        /// - Parameter account: The account to save.
        init(_ account: Account) {
            id = account.id
            recoveryID = account.recoveryID
            address = account.address.value
            path = account.path.description
            name = account.customName
        }

        /// Returns the account after checking its address and path.
        ///
        /// - Returns: The account.
        /// - Throws: An address or derivation path validation error.
        func account() throws -> Account {
            Account(id: id, recoveryID: recoveryID, address: try Address(address), path: try DerivationPath(path),
                    customName: name)
        }
    }
}

extension ValueCoding where Self == AccountsCoding {
    nonisolated static var accounts: AccountsCoding { AccountsCoding() }
}
