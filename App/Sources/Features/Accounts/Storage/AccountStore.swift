import Foundation
import Observation
import Storage
import Wallet

/// The saved accounts that every window shares, so an account saved in one window shows in the others at once.
///
/// The store reads nothing until ``load()``, whose read first finishes the launch cleanup of recovery that no saved
/// account references. Each addition, rename, or deletion shows at once and saves after the changes made before it; a
/// change that can't be saved is undone and throws.
@MainActor
@Observable
final class AccountStore {
    private let list: PersistentValue<[Account]>

    /// Connects to the storage that keeps the accounts, without reading it or running the cleanup.
    /// - Parameters:
    ///   - storage: The storage that keeps the accounts.
    ///   - cleanup: The launch cleanup, which reads the same storage before it deletes unreferenced recovery.
    init(storage: any ValueStoring<[Account]>, cleanup: any RecoveryCleaning) {
        list = PersistentValue(storage: CleanedUpStorage(storage: storage, cleanup: cleanup), empty: [])
    }

    /// The file that keeps the accounts in a directory.
    /// - Parameter directory: The directory that keeps the Accounts files.
    /// - Returns: The accounts file, which isn't created or read yet.
    nonisolated static func file(in directory: URL) -> FileItem<AccountsCoding> {
        FileItem(url: directory.appending(path: "accounts.json"), coding: .accounts)
    }

    /// The saved accounts with every addition made so far, in the order they were added, or an empty list before
    /// they're read.
    var accounts: [Account] { list.value }

    /// Whether the saved accounts were read; a failed launch cleanup also leaves them unreadable, so no window opens
    /// onboarding over recovery that wasn't deleted.
    var phase: PersistentValuePhase { list.phase }

    /// Finishes the launch cleanup and reads the saved accounts, unless they were already read, and returns once the
    /// additions made before this call are saved or undone.
    ///
    /// A failed cleanup or read sets ``phase`` to ``PersistentValuePhase/unreadable``; nothing saved is deleted or
    /// replaced, so calling this method again tries again.
    func load() async {
        await list.load()
    }

    /// Saves an account after the saved ones.
    /// - Parameter account: The account, whose recovery is already saved.
    /// - Throws: ``AccountStoreError/duplicateAccount`` when an account with the same identity, address, or recovery
    ///   and path is saved, or a storage error after undoing the addition.
    func add(_ account: Account) async throws {
        guard !accounts.contains(where: { $0.isDuplicate(of: account) }) else {
            throw AccountStoreError.duplicateAccount
        }
        try await list.update { $0.append(account) }
    }

    /// Saves an account's new name, which shows at once; an empty name gives the account back its numbered name.
    /// - Parameters:
    ///   - id: The account's identity; nothing changes once the account is no longer saved.
    ///   - name: The new name; spaces and line breaks around it are ignored.
    /// - Throws: A storage error after undoing the change.
    func rename(_ id: Account.ID, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = trimmed.isEmpty ? nil : trimmed
        try await list.update { accounts in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].customName = customName
        }
    }

    /// Deletes an account, which leaves every window's list at once; its funds stay at its address.
    /// - Parameter id: The account's identity; nothing changes once the account is no longer saved.
    /// - Throws: A storage error after undoing the deletion.
    func remove(_ id: Account.ID) async throws {
        try await list.update { accounts in accounts.removeAll { $0.id == id } }
    }

    /// The saved accounts of a wallet.
    /// - Parameter recoveryID: The wallet's recovery identifier.
    /// - Returns: The wallet's accounts, in the order they were added.
    func accounts(inWallet recoveryID: UUID) -> [Account] {
        accounts.filter { $0.recoveryID == recoveryID }
    }

    /// The path of a wallet's next account: `m/44'/501'/i'/0'`, where i is the lowest account index that none of the
    /// wallet's accounts uses, in either Solana account family, so no two accounts share a numbered name.
    /// - Parameter recoveryID: The wallet's recovery identifier.
    /// - Returns: The path for a new account.
    func nextPath(inWallet recoveryID: UUID) -> DerivationPath {
        let used = Set(accounts(inWallet: recoveryID).compactMap(\.path.accountIndex))
        var index: UInt32 = 0
        while used.contains(index) { index += 1 }
        return .solana(account: index)
    }

    /// Deletes the saved accounts after the additions made before it, so every window forgets them.
    /// - Throws: A storage error, which keeps the accounts.
    func erase() async throws {
        try await list.erase()
    }

    /// The accounts' storage, whose reads wait for the launch cleanup, so the cleanup counts as part of reading.
    nonisolated private struct CleanedUpStorage: ValueStoring {
        let storage: any ValueStoring<[Account]>
        let cleanup: any RecoveryCleaning

        /// Finishes the launch cleanup, then reads the saved accounts.
        /// - Returns: The accounts, or `nil` before any are saved.
        /// - Throws: A cleanup, storage, or cancellation error.
        func load() async throws -> [Account]? {
            try await cleanup.complete()
            return try await storage.load()
        }

        /// Saves the accounts, replacing the saved ones.
        /// - Parameter value: The accounts.
        /// - Throws: A storage or cancellation error.
        func save(_ value: [Account]) async throws {
            try await storage.save(value)
        }

        /// Deletes the saved accounts.
        /// - Throws: A storage or cancellation error.
        func delete() async throws {
            try await storage.delete()
        }

        /// Reads, changes, and saves the accounts in one step.
        /// - Parameter change: Changes the saved accounts.
        /// - Returns: The change's result.
        /// - Throws: The change's error, or a storage or cancellation error.
        func update<Result: Sendable>(
            _ change: @escaping @Sendable (inout [Account]?) throws -> Result
        ) async throws -> Result {
            try await storage.update(change)
        }
    }
}
