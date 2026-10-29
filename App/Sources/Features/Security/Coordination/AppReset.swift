import Foundation
import Vault

/// Deletes recovery phrases first, so a failed later step never leaves secrets behind, and the saved accounts last, so
/// every window stays on its wallet until everything else is deleted.
@MainActor
struct AppReset: AppResetting {
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private let directories: [URL]
    private let appearance: any AppearanceCoordinating
    private let stores: [any Erasable]
    private let accounts: any Erasable
    private let revision: Revision

    /// Connects the reset to every store that holds the person's data.
    /// - Parameters:
    ///   - recovery: The protected recovery storage.
    ///   - privateBalances: Each account's private-balance keys, notes, and redeem codes.
    ///   - directories: The directories that hold every other kept and cached file, such as wallets and themes.
    ///   - appearance: The shared appearance, which forgets its cached selections once the directories are gone.
    ///   - stores: The shared stores, such as the contacts, the transactions, the currency choice, the provider
    ///     settings, and the balances, which end their work before the directories are deleted, so nothing they started
    ///     saves into them afterward.
    ///   - accounts: The saved accounts, which are erased last, so a failed earlier step keeps every window on its
    ///     wallet, where it can try again.
    ///   - revision: Tells every window when the reset finishes.
    init(recovery: any RecoveryStoring, privateBalances: any PrivateBalancing, directories: [URL],
         appearance: any AppearanceCoordinating, stores: [any Erasable], accounts: any Erasable,
         revision: Revision) {
        self.recovery = recovery
        self.privateBalances = privateBalances
        self.directories = directories
        self.appearance = appearance
        self.stores = stores
        self.accounts = accounts
        self.revision = revision
    }

    /// Deletes every recovery phrase, then the private-balance keys, notes, and redeem codes, erases each shared store,
    /// deletes the directories, restarts appearance, erases the saved accounts, and returns every window to onboarding.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws {
        try await recovery.deleteAllRecovery()
        try await privateBalances.removeAll()
        for store in stores { try await store.erase() }
        try await Self.delete(directories)
        try await appearance.restart()
        try await accounts.erase()
        revision.advance()
    }

    /// Deletes each directory with everything inside it, away from the main actor, since themes can hold many files.
    /// - Parameter directories: The directories to delete; a missing one is already deleted.
    /// - Throws: A filesystem error from the first directory that can't be deleted.
    @concurrent
    private static func delete(_ directories: [URL]) async throws {
        for directory in directories {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch CocoaError.fileNoSuchFile {}
        }
    }
}
