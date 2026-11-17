import Observation
import SwiftUI
import Synchronization
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PaletteObservationTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func `Reloading identical colors does not notify`(scheme: ColorScheme) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let rendered = RenderedAppearance()
        let changed = Mutex(false)
        withObservationTracking {
            _ = rendered.palette(scheme: scheme)
        } onChange: {
            changed.withLock { $0 = true }
        }

        try await rendered.load(nil, catalog: catalog)

        let notified = changed.withLock(\.self)
        #expect(!notified)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `Changing a dark color only notifies dark observers`(scheme: ColorScheme) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let source = try fixture.source(tokens: ["colors": ["dark": ["primary": ["srgb": "#123456"]]]])
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: source))
        let rendered = RenderedAppearance()
        let changed = Mutex(false)
        withObservationTracking {
            _ = rendered.palette(scheme: scheme)
        } onChange: {
            changed.withLock { $0 = true }
        }

        try await rendered.load(entry, catalog: catalog)

        let notified = changed.withLock(\.self)
        #expect(notified == (scheme == .dark))
    }
}
