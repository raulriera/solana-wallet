import Foundation
import Themes
@testable import widgets

/// Owns isolated source and installation directories for one catalog test.
nonisolated struct CatalogFixture {
    let root: URL
    let directory: URL

    /// Creates unique local storage without touching the app's real theme directory.
    /// - Throws: A fixture filesystem error.
    init() throws {
        root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directory = root.appendingPathComponent("Installed")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Creates a real minimal package with caller-selected identity and name.
    /// - Parameters:
    ///   - id: The identity used to exercise collisions and replacement.
    ///   - name: The theme name, independent of identity.
    /// - Returns: A package URL accepted by the real framework reader.
    /// - Throws: A fixture encoding or filesystem error.
    func source(id: UUID = UUID(), name: String = "Example") throws -> URL {
        let source = root.appendingPathComponent(UUID().uuidString + ".xtheme")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let json: [String: Any] = ["version": 1, "id": id.uuidString, "name": name]
        try JSONSerialization.data(withJSONObject: json).write(to: source.appendingPathComponent("manifest.json"))
        return source
    }

    /// Removes this test's directories after all child operations finish.
    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// Intercepts saving for deterministic failures and cancellation while retaining real package behavior.
nonisolated struct InterceptedPackages: PackServicing {
    /// Injects a failure or suspension after staging and before catalog commit.
    typealias SaveHook = @Sendable () async throws -> Void

    let afterSave: SaveHook

    /// Creates an interception point after package staging, before catalog commit.
    /// - Parameter afterSave: A test-controlled failure or suspension.
    init(afterSave: @escaping SaveHook) { self.afterSave = afterSave }

    /// Loads a real validated snapshot.
    /// - Parameter url: The source package.
    /// - Returns: Owned package data.
    /// - Throws: A package read error.
    func read(from url: URL) async throws -> Pack { try await PackService().read(from: url) }

    /// Writes a real staged package before invoking the test interception.
    /// - Parameters:
    ///   - pack: The validated snapshot.
    ///   - url: Its staged destination.
    /// - Throws: A write error or the injected failure.
    func save(_ pack: Pack, to url: URL) async throws {
        try await PackService().save(pack, to: url)
        try await afterSave()
    }

    /// Resolves real framework colors.
    /// - Parameters:
    ///   - pack: The validated snapshot.
    ///   - defaults: The caller's complete palettes.
    /// - Returns: Resolved colors.
    func resolve(_ pack: Pack, defaults: Colors) -> Colors { PackService().resolve(pack, defaults: defaults) }

    /// Exports a template through the real service.
    /// - Parameters:
    ///   - name: The template name.
    ///   - defaults: Complete exported colors.
    ///   - url: The template destination.
    /// - Throws: An export error.
    func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws {
        try await PackService().exportTemplate(named: name, defaults: defaults, to: url)
    }
}
