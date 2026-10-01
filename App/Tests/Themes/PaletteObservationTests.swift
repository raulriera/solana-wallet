import Foundation
import Observation
import SwiftUI
import Synchronization
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PaletteObservationTests {
    /// Reloading identical colors does not invalidate protocol consumers of any appearance variant.
    /// - Parameters:
    ///   - scheme: The consumer's light or dark appearance.
    ///   - contrast: The consumer's standard or increased contrast.
    /// - Throws: A fixture or theme-loading error.
    @Test(arguments: [ColorScheme.light, .dark], [ColorSchemeContrast.standard, .increased])
    func reloadingIdenticalColorsDoesNotNotify(scheme: ColorScheme, contrast: ColorSchemeContrast) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let rendered = RenderedAppearance()
        let palettes: any PaletteProviding = rendered
        let changed = Mutex(false)
        withObservationTracking {
            _ = palettes.palette(scheme: scheme, contrast: contrast)
        } onChange: {
            changed.withLock { $0 = true }
        }

        try await rendered.load(nil, catalog: catalog, packages: PackService())

        let notified = changed.withLock(\.self)
        #expect(!notified)
    }

    /// Every semantic color remains observable through the protocol when a package changes its value.
    /// - Parameters:
    ///   - role: The manifest color role changed from the original appearance.
    ///   - observesChangedVariant: Whether the consumer reads the changed contrast variant.
    /// - Throws: A fixture, package-installation, or theme-loading error.
    @Test(arguments: ["background", "surface", "primaryText", "secondaryText", "separator", "accent", "onAccent"],
          [true, false])
    func changingColorOnlyNotifiesAffectedVariant(role: String, observesChangedVariant: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let manifestURL = source.appendingPathComponent("manifest.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["tokens"] = ["colors": ["darkIncreasedContrast": [role: ["srgb": "#123456"]]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        let palettes: any PaletteProviding = rendered
        let changed = Mutex(false)
        withObservationTracking {
            _ = palettes.palette(scheme: .dark, contrast: observesChangedVariant ? .increased : .standard)
        } onChange: {
            changed.withLock { $0 = true }
        }

        try await rendered.load(entry, catalog: catalog, packages: PackService())

        let notified = changed.withLock(\.self)
        #expect(notified == observesChangedVariant)
    }
}
