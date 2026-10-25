import Foundation
import Storage
import Vault

/// Deletes recovery phrases first, so a failed later step never leaves secrets behind.
@MainActor
struct AppReset: AppResetting {
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private let directories: [URL]
    private let appearance: any AppearanceCoordinating
    private let contacts: ContactStore
    private let providerKey: any ValueStoring<String>
    private let providerSettings: any ValueStoring<ProviderSettings>
    private let revision: Revision

    /// Connects the reset to every store that holds the person's data.
    /// - Parameters:
    ///   - recovery: The protected recovery storage.
    ///   - privateBalances: Each account's private-balance keys, notes, and redeem codes.
    ///   - directories: The directories that hold every other kept and cached file, such as wallets and themes.
    ///   - appearance: The shared appearance, which forgets its cached selections once the directories are gone.
    ///   - contacts: The shared contacts, which every window forgets once the directories are gone.
    ///   - providerKey: The provider's API key storage.
    ///   - providerSettings: The provider choice and custom RPC storage.
    ///   - revision: Tells every window when the reset finishes.
    init(recovery: any RecoveryStoring, privateBalances: any PrivateBalancing, directories: [URL],
         appearance: any AppearanceCoordinating, contacts: ContactStore, providerKey: any ValueStoring<String>,
         providerSettings: any ValueStoring<ProviderSettings>, revision: Revision) {
        self.recovery = recovery
        self.privateBalances = privateBalances
        self.directories = directories
        self.appearance = appearance
        self.contacts = contacts
        self.providerKey = providerKey
        self.providerSettings = providerSettings
        self.revision = revision
    }

    /// Deletes every recovery phrase, then the private-balance keys, notes, and redeem codes, then the directories,
    /// restarts appearance, erases the contacts, then deletes the provider API key, then the provider choice and custom
    /// RPCs, and returns every window to onboarding.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws {
        try await recovery.deleteAllRecovery()
        try await privateBalances.removeAll()
        try await Self.delete(directories)
        try await appearance.restart()
        try await contacts.erase()
        try await providerKey.delete()
        try await providerSettings.delete()
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
