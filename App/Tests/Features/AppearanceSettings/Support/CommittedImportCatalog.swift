import Foundation
import Themes
@testable import widgets

nonisolated struct CommittedImportCatalog: ThemeCatalogProviding {
    let base: any ThemeCatalogProviding
    let afterCommit: @Sendable () async -> Void

    func entries() async throws -> [ThemeEntry] { try await base.entries() }

    func install(_ pack: Pack, replacing existing: ThemeEntry?) async throws -> ThemeEntry {
        let entry = try await base.install(pack, replacing: existing)
        await afterCommit()
        return entry
    }

    func pack(for entry: ThemeEntry) async throws -> Pack { try await base.pack(for: entry) }

    func remove(_ entry: ThemeEntry) async throws { try await base.remove(entry) }
}
