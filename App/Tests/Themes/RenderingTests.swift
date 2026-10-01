import Foundation
import SwiftUI
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceRenderingTests {
    /// Each window uses its own appearance and contrast variant from one loaded snapshot.
    @Test func resolvesFourIndependentVariants() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let manifestURL = source.appendingPathComponent("manifest.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["tokens"] = ["colors": [
            "light": ["accent": ["srgb": "#FF0000"]],
            "dark": ["accent": ["srgb": "#00FF00"]],
            "lightIncreasedContrast": ["accent": ["srgb": "#0000FF"]],
            "darkIncreasedContrast": ["accent": ["srgb": "#FFFFFF"]]
        ]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        try await rendered.load(entry, catalog: catalog, packages: PackService())
        // Removing storage after load proves trait selection needs no further package reads.
        fixture.remove()
        let environment = EnvironmentValues()
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent.resolve(in: environment).red == 1)
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent.resolve(in: environment).green == 0)
        #expect(rendered.palette(scheme: .dark, contrast: .standard).accent.resolve(in: environment).green == 1)
        #expect(rendered.palette(scheme: .light, contrast: .increased).accent.resolve(in: environment).blue == 1)
        #expect(rendered.palette(scheme: .dark, contrast: .increased).accent.resolve(in: environment).red == 1)
    }

    /// An unreadable selected revision restores native colors and reports the failure.
    @Test func unreadableThemeFallsBackToOriginal() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let id = UUID()
        let source = try fixture.source(id: id)
        let json: [String: Any] = ["version": 1, "id": id.uuidString, "name": "Custom",
                                   "tokens": ["colors": ["light": ["accent": ["srgb": "#FF0000"]]]]]
        try JSONSerialization.data(withJSONObject: json).write(to: source.appendingPathComponent("manifest.json"))
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        try await rendered.load(entry, catalog: catalog, packages: PackService())
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent != RenderedPalette(OriginalAppearance.palette).accent)
        try await catalog.remove(entry)
        await #expect(throws: ThemeCatalog.Failure.changed) {
            try await rendered.load(entry, catalog: catalog, packages: PackService())
        }
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent == RenderedPalette(OriginalAppearance.palette).accent)
    }
}
