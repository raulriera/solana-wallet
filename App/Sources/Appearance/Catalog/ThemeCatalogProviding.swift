import Foundation
import Themes

/// Owns installed theme packages; appearance selections and rendering belong to callers.
nonisolated protocol ThemeCatalogProviding: Sendable {
    /// Lists lightweight metadata without loading package assets.
    /// - Returns: Built-in and custom entries; callers choose presentation order.
    /// - Throws: A storage or cancellation error rather than an incomplete catalog.
    func entries() async throws -> [ThemeEntry]

    /// Installs a validated snapshot without activating it.
    /// - Parameters:
    ///   - pack: The snapshot returned by the package service after Files import.
    ///   - existing: The exact custom revision the user approved replacing, or `nil` for a new identity.
    /// - Returns: The committed custom entry.
    /// - Throws: A conflict, immutable-theme, storage, or pre-commit cancellation error.
    func install(_ pack: Pack, replacing existing: ThemeEntry?) async throws -> ThemeEntry

    /// Loads one selected revision, retaining no package or image cache in the catalog.
    /// - Parameter entry: The current entry being selected or exported.
    /// - Returns: An independently owned validated package.
    /// - Throws: A stale-entry, missing-package, validation, storage, or cancellation error.
    func pack(for entry: ThemeEntry) async throws -> Pack

    /// Removes the exact custom revision and clears its application and wallet selections atomically.
    /// - Parameter entry: The entry to remove; built-ins are immutable.
    /// - Throws: A stale-entry, immutable-theme, storage, or pre-commit cancellation error.
    func remove(_ entry: ThemeEntry) async throws
}

extension ThemeCatalogProviding {
    /// Installs a new identity without permitting replacement.
    /// - Parameter pack: The validated imported snapshot.
    /// - Returns: The committed custom entry.
    /// - Throws: A catalog conflict, storage, or cancellation error.
    func install(_ pack: Pack) async throws -> ThemeEntry {
        try await install(pack, replacing: nil)
    }
}
