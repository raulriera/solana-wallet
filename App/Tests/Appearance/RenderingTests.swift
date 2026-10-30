import Foundation
import SwiftUI
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceRenderingTests {
    @Test func `Resolves four independent variants`() async throws {
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
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        try await rendered.load(entry, catalog: catalog, packages: PackService())
        fixture.remove()
        let environment = EnvironmentValues()
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent.resolve(in: environment).red == 1)
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent.resolve(in: environment).green == 0)
        #expect(rendered.palette(scheme: .dark, contrast: .standard).accent.resolve(in: environment).green == 1)
        #expect(rendered.palette(scheme: .light, contrast: .increased).accent.resolve(in: environment).blue == 1)
        #expect(rendered.palette(scheme: .dark, contrast: .increased).accent.resolve(in: environment).red == 1)
    }

    @Test func `Unreadable theme falls back to original`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
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
        await #expect(throws: ThemeCatalogError.changed) {
            try await rendered.load(entry, catalog: catalog, packages: PackService())
        }
        #expect(rendered.palette(scheme: .light, contrast: .standard).accent == RenderedPalette(OriginalAppearance.palette).accent)
    }
}
