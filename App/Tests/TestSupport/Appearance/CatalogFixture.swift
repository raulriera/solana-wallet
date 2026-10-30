import Foundation
import Themes
@testable import widgets

nonisolated struct CatalogFixture {
    let root: URL
    let directory: URL

    init() throws {
        root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directory = root.appendingPathComponent("Installed")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func source(id: UUID = UUID(), name: String = "Example") throws -> URL {
        let source = root.appendingPathComponent(UUID().uuidString + ".xtheme")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let json: [String: Any] = ["version": 1, "id": id.uuidString, "name": name]
        try JSONSerialization.data(withJSONObject: json).write(to: source.appendingPathComponent("manifest.json"))
        return source
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

nonisolated struct InterceptedPackages: PackServicing {
    typealias SaveHook = @Sendable () async throws -> Void

    let afterSave: SaveHook

    init(afterSave: @escaping SaveHook) { self.afterSave = afterSave }

    func read(from url: URL) async throws -> Pack { try await PackService().read(from: url) }

    func save(_ pack: Pack, to url: URL) async throws {
        try await PackService().save(pack, to: url)
        try await afterSave()
    }

    func resolve(_ pack: Pack, defaults: Colors) -> Colors { PackService().resolve(pack, defaults: defaults) }

    func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws {
        try await PackService().exportTemplate(named: name, defaults: defaults, to: url)
    }
}
