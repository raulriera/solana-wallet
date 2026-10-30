import Foundation
import Observation
import Storage
import Wallet

/// The saved accounts of every wallet.
@MainActor
@Observable
final class AccountStore: Erasable {
    private let list: PersistentValue<[Account]>

    /// Creates a store without reading the accounts.
    ///
    /// - Parameters:
    ///   - storage: The storage that keeps the accounts.
    ///   - cleanup: The cleanup to finish before reading the accounts.
    init(storage: any ValueStoring<[Account]>, cleanup: any RecoveryCleaning) {
        list = PersistentValue(storage: CleanedUpStorage(storage: storage, cleanup: cleanup), empty: [])
    }

    /// Returns the file that keeps the accounts in a directory.
    ///
    /// - Parameter directory: The directory of the file.
    /// - Returns: The accounts file.
    nonisolated static func file(in directory: URL) -> FileItem<AccountsCoding> {
        FileItem(url: directory.appending(path: "accounts.json"), coding: .accounts)
    }

    /// The accounts in the order they were added, or an empty list before they're read.
    var accounts: [Account] { list.value }

    var phase: PersistentValuePhase { list.phase }

    /// Finishes the launch cleanup and reads the saved accounts, unless they were already read.
    func load() async {
        await list.load()
    }

    /// Saves an account after the saved ones.
    ///
    /// - Parameter account: The account to save.
    /// - Throws: ``AccountStoreError/duplicateAccount`` for a duplicate account, or a storage error.
    func add(_ account: Account) async throws {
        guard !accounts.contains(where: { $0.isDuplicate(of: account) }) else {
            throw AccountStoreError.duplicateAccount
        }
        try await list.update { $0.append(account) }
    }

    /// Saves an account's new name without the whitespace around it.
    ///
    /// - Parameters:
    ///   - id: The account's identifier.
    ///   - name: The new name, or an empty string for the account's numbered name.
    /// - Throws: A storage error.
    func rename(_ id: Account.ID, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = trimmed.isEmpty ? nil : trimmed
        try await list.update { accounts in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].customName = customName
        }
    }

    /// Deletes an account.
    ///
    /// - Parameter id: The account's identifier.
    /// - Throws: A storage error.
    func remove(_ id: Account.ID) async throws {
        try await list.update { accounts in accounts.removeAll { $0.id == id } }
    }

    /// Returns the saved accounts of a wallet.
    ///
    /// - Parameter recoveryID: The wallet's recovery identifier.
    /// - Returns: The wallet's accounts, in the order they were added.
    func accounts(inWallet recoveryID: UUID) -> [Account] {
        accounts.filter { $0.recoveryID == recoveryID }
    }

    /// Returns the path of a wallet's next account at the lowest account index that its accounts don't use.
    ///
    /// - Parameter recoveryID: The wallet's recovery identifier.
    /// - Returns: The path `m/44'/501'/i'/0'` for the new account.
    func nextPath(inWallet recoveryID: UUID) -> DerivationPath {
        let used = Set(accounts(inWallet: recoveryID).compactMap(\.path.accountIndex))
        var index: UInt32 = 0
        while used.contains(index) { index += 1 }
        return .solana(account: index)
    }

    func erase() async throws {
        try await list.erase()
    }

    /// A storage of the accounts that finishes the launch cleanup before each read.
    nonisolated private struct CleanedUpStorage: ValueStoring {
        let storage: any ValueStoring<[Account]>
        let cleanup: any RecoveryCleaning

        func load() async throws -> [Account]? {
            try await cleanup.complete()
            return try await storage.load()
        }

        func save(_ value: [Account]) async throws {
            try await storage.save(value)
        }

        func delete() async throws {
            try await storage.delete()
        }

        func update<Result: Sendable>(
            _ change: @escaping @Sendable (inout [Account]?) throws -> Result
        ) async throws -> Result {
            try await storage.update(change)
        }
    }
}
