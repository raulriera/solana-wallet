import Foundation
import Vault

/// Deletes recovery phrases first, so a failed later step never leaves secrets behind.
@MainActor
struct AppReset: AppResetting {
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private let directories: [URL]
    private let appearance: any AppearanceCoordinating
    private let stores: [any Erasable]
    private let revision: Revision

    /// Connects the reset to every store that holds the person's data.
    /// - Parameters:
    ///   - recovery: The protected recovery storage.
    ///   - privateBalances: Each account's private-balance keys, notes, and redeem codes.
    ///   - directories: The directories that hold every other kept and cached file, such as wallets and themes.
    ///   - appearance: The shared appearance, which forgets its cached selections once the directories are gone.
    ///   - stores: The shared stores, such as the contacts, the accounts, the transactions, the currency choice, and
    ///     the provider settings, which every window forgets once the directories are gone.
    ///   - revision: Tells every window when the reset finishes.
    init(recovery: any RecoveryStoring, privateBalances: any PrivateBalancing, directories: [URL],
         appearance: any AppearanceCoordinating, stores: [any Erasable], revision: Revision) {
        self.recovery = recovery
        self.privateBalances = privateBalances
        self.directories = directories
        self.appearance = appearance
        self.stores = stores
        self.revision = revision
    }

    /// Deletes every recovery phrase, then the private-balance keys, notes, and redeem codes, then the directories,
    /// restarts appearance, erases each shared store, and returns every window to onboarding.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws {
        try await recovery.deleteAllRecovery()
        try await privateBalances.removeAll()
        try await Self.delete(directories)
        try await appearance.restart()
        for store in stores { try await store.erase() }
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
