import Foundation
import SwiftUI
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceRenderingTests {
    @Test func `Resolves independent light and dark variants`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let source = try fixture.source(tokens: ["colors": [
            "light": ["primary": ["srgb": "#FF0000"]],
            "dark": ["primary": ["srgb": "#00FF00"]]
        ]])
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        try await rendered.load(entry, catalog: catalog)
        fixture.remove()
        let environment = EnvironmentValues()
        #expect(rendered.palette(scheme: .light).primary.resolve(in: environment).red == 1)
        #expect(rendered.palette(scheme: .light).primary.resolve(in: environment).green == 0)
        #expect(rendered.palette(scheme: .dark).primary.resolve(in: environment).green == 1)
        #expect(rendered.palette(scheme: .dark).primary.resolve(in: environment).red == 0)
    }

    @Test(arguments: [("default", Font.Design.default), ("rounded", .rounded), ("serif", .serif), ("monospaced", .monospaced)])
    func `Renders the theme's font design`(token: String, design: Font.Design) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source(tokens: ["fontDesign": token])))
        let rendered = RenderedAppearance()
        try await rendered.load(entry, catalog: catalog)
        #expect(rendered.fontDesign == design)
    }

    @Test(arguments: [true, false])
    func `Switching from a serif theme renders the original design`(toOmittedTheme: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let source = try fixture.source(tokens: ["fontDesign": "serif"])
        let custom = try await catalog.install(PackService().read(from: source))
        let next = try await toOmittedTheme ? catalog.install(PackService().read(from: fixture.source())) : nil
        let rendered = RenderedAppearance()
        try await rendered.load(custom, catalog: catalog)
        try await rendered.load(next, catalog: catalog)
        #expect(rendered.fontDesign == .default)
    }

    @Test func `Unreadable theme falls back to original`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let source = try fixture.source(name: "Custom", tokens: [
            "colors": ["light": ["primary": ["srgb": "#FF0000"]]], "fontDesign": "serif"
        ])
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        try await rendered.load(entry, catalog: catalog)
        #expect(rendered.palette(scheme: .light).primary != RenderedPalette(OriginalAppearance.palette).primary)
        #expect(rendered.fontDesign == .serif)
        try await catalog.remove(entry)
        await #expect(throws: ThemeCatalogError.changed) {
            try await rendered.load(entry, catalog: catalog)
        }
        #expect(rendered.palette(scheme: .light).primary == RenderedPalette(OriginalAppearance.palette).primary)
        #expect(rendered.fontDesign == .default)
    }
}
