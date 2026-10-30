import Foundation
import Themes

/// A catalog of bundled and installed theme packages.
nonisolated protocol ThemeCatalogProviding: Sendable {
    /// Lists the bundled and installed themes without loading their packages.
    ///
    /// - Returns: The entries, in no particular order.
    /// - Throws: A storage or cancellation error.
    func entries() async throws -> [ThemeEntry]

    /// Installs a theme package without selecting it.
    ///
    /// - Parameters:
    ///   - pack: The validated package.
    ///   - existing: The installed theme to replace, or `nil` to add a new theme.
    /// - Returns: The installed entry.
    /// - Throws: A conflict, built-in theme, storage, or cancellation error.
    func install(_ pack: Pack, replacing existing: ThemeEntry?) async throws -> ThemeEntry

    /// Loads the package of a theme.
    ///
    /// - Parameter entry: The theme to load.
    /// - Returns: The validated package.
    /// - Throws: A changed-entry, validation, storage, or cancellation error.
    func pack(for entry: ThemeEntry) async throws -> Pack

    /// Removes an installed theme and clears every selection of it.
    ///
    /// - Parameter entry: The installed theme to remove.
    /// - Throws: A built-in theme, changed-entry, storage, or cancellation error.
    func remove(_ entry: ThemeEntry) async throws
}

extension ThemeCatalogProviding {
    /// Installs a theme package that isn't installed yet.
    ///
    /// - Parameter pack: The validated package.
    /// - Returns: The installed entry.
    /// - Throws: A conflict, storage, or cancellation error.
    func install(_ pack: Pack) async throws -> ThemeEntry {
        try await install(pack, replacing: nil)
    }
}
