import Foundation
import Vault

/// Resets the app by deleting its secrets, stores, files, and saved accounts.
@MainActor
struct AppReset: AppResetting {
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private let directories: [URL]
    private let appearance: any AppearanceCoordinating
    private let stores: [any Erasable]
    private let accounts: any Erasable

    /// Creates a reset.
    ///
    /// - Parameters:
    ///   - recovery: The recovery storage.
    ///   - privateBalances: The private-balance keys, notes, and redeem codes.
    ///   - directories: The directories to delete.
    ///   - appearance: The shared appearance to restart.
    ///   - stores: The shared stores to erase.
    ///   - accounts: The saved accounts to erase last.
    init(recovery: any RecoveryStoring, privateBalances: any PrivateBalancing, directories: [URL],
         appearance: any AppearanceCoordinating, stores: [any Erasable], accounts: any Erasable) {
        self.recovery = recovery
        self.privateBalances = privateBalances
        self.directories = directories
        self.appearance = appearance
        self.stores = stores
        self.accounts = accounts
    }

    func reset() async throws {
        try await recovery.deleteAllRecovery()
        try await privateBalances.removeAll()
        for store in stores { try await store.erase() }
        try await Self.delete(directories)
        try await appearance.restart()
        try await accounts.erase()
    }

    /// Deletes each directory and its contents.
    ///
    /// - Parameter directories: The directories to delete.
    /// - Throws: A file system error from the first directory that can't be deleted.
    @concurrent
    private static func delete(_ directories: [URL]) async throws {
        for directory in directories {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch CocoaError.fileNoSuchFile {}
        }
    }
}
