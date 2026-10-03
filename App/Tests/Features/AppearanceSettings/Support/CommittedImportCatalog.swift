import Foundation
import Themes
@testable import widgets

/// Suspends after a real catalog commit so window closure can race with publication.
nonisolated struct CommittedImportCatalog: ThemeCatalogProviding {
    let base: any ThemeCatalogProviding
    let afterCommit: @Sendable () async -> Void

    /// Reads real catalog metadata.
    /// - Returns: The installed entries.
    /// - Throws: A catalog read error.
    func entries() async throws -> [ThemeEntry] { try await base.entries() }

    /// Commits real files before suspending at the test's deterministic boundary.
    /// - Parameters:
    ///   - pack: The validated source.
    ///   - existing: The approved replacement revision, if any.
    /// - Returns: The committed entry, including when cancellation follows the commit.
    /// - Throws: A pre-commit installation error.
    func install(_ pack: Pack, replacing existing: ThemeEntry?) async throws -> ThemeEntry {
        let entry = try await base.install(pack, replacing: existing)
        await afterCommit()
        return entry
    }

    /// Reads a real installed package.
    /// - Parameter entry: The expected installed revision.
    /// - Returns: Its validated snapshot.
    /// - Throws: A catalog or package read error.
    func pack(for entry: ThemeEntry) async throws -> Pack { try await base.pack(for: entry) }

    /// Removes a real installed entry.
    /// - Parameter entry: The expected custom revision.
    /// - Throws: A removal error.
    func remove(_ entry: ThemeEntry) async throws { try await base.remove(entry) }
}
