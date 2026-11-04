import Foundation
import Testing
@testable import Themes

struct ExportTests {
    @Test func `Installed copy preserves overrides instead of freezing defaults`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.asset(Fixture.image())
        try fixture.manifest(##""tokens":{"colors":{"light":{"primary":{"srgb":"#12AB34"}}}},"assets":{"image":"Assets/image.png"}"##)
        let service: any PackServicing = PackService()
        let original = try await service.read(from: fixture.source)
        try FileManager.default.removeItem(at: fixture.source)
        let destination = fixture.directory.appendingPathComponent("Installed.xtheme")
        try await service.save(original, to: destination)
        let installed = try await service.read(from: destination)
        #expect(installed.id == original.id)
        #expect(installed.assets == original.assets)
        let palette = Fixture.palette(.system(.systemRed))
        let different = Colors(light: palette, dark: palette, lightIncreasedContrast: palette, darkIncreasedContrast: palette)
        #expect(service.resolve(installed, defaults: different) == service.resolve(original, defaults: different))
        #expect(service.resolve(installed, defaults: different).light.background == .system(.systemRed))
        let json = try Fixture.exportedJSON(at: destination)
        let tokens = try #require(json["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: [String: String]]])
        #expect(Set(colors.keys) == ["light"])
        #expect(Set(try #require(colors["light"]).keys) == ["primary"])
    }

    @Test func `Template exports complete defaults with new identities`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service: any PackServicing = PackService()
        let first = fixture.directory.appendingPathComponent("First")
        let second = fixture.directory.appendingPathComponent("Second")
        try await service.exportTemplate(named: "Template", defaults: Fixture.defaults, to: first)
        try await service.exportTemplate(named: "Template", defaults: Fixture.defaults, to: second)
        let a = try await service.read(from: first)
        let b = try await service.read(from: second)
        #expect(a.id != b.id)
        #expect(a.name == "Template")
        #expect(a.assets.isEmpty)
        let alternate = Colors(light: Fixture.defaults.dark, dark: Fixture.defaults.light,
                               lightIncreasedContrast: Fixture.defaults.dark, darkIncreasedContrast: Fixture.defaults.light)
        #expect(service.resolve(a, defaults: alternate) == Fixture.defaults)
        let json = try Fixture.exportedJSON(at: first)
        #expect(json["version"] as? Int == 1)
        #expect(json["formatVersion"] == nil)
        let tokens = try #require(json["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: [String: String]]])
        #expect(Set(colors.keys) == ["light", "dark", "lightIncreasedContrast", "darkIncreasedContrast"])
        for palette in colors.values {
            #expect(Set(palette.keys) == ["background", "surface", "text", "secondaryText", "separator", "primary",
                                           "onPrimary", "secondary", "onSecondary", "destructive", "onDestructive"])
        }
        #expect(colors["light"]?["background"] == ["system": "systemBackground"])
    }

    @Test func `Saved copy preserves shared assets and identity`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let png = try Fixture.image()
        let jpeg = try Fixture.image(type: "public.jpeg")
        try fixture.asset(png, path: "Assets/nested/texture.png")
        try fixture.asset(jpeg, path: "Assets/background.jpg")
        try fixture.manifest(##""tokens":{"colors":{"light":{"primary":{"srgb":"#12aB34"}}}},"assets":{"texture":"Assets/nested/texture.png","background":"Assets/background.jpg","shared":"Assets/nested/texture.png"}"##)
        let service = PackService()
        let original = try await service.read(from: fixture.source)
        let expected = service.resolve(original, defaults: Fixture.defaults)
        try FileManager.default.removeItem(at: fixture.source)
        let destination = fixture.directory.appendingPathComponent("Renamed")
        try await service.save(original, to: destination)
        let saved = try await service.read(from: destination)
        #expect(saved.id == Fixture.id)
        #expect(saved.name == original.name)
        #expect(saved.assets == original.assets)
        #expect(service.resolve(saved, defaults: Fixture.defaults) == expected)
        let manifest = try Fixture.exportedJSON(at: destination)
        let tokens = try #require(manifest["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: [String: String]]])
        #expect(colors["light"]?["primary"] == ["srgb": "#12AB34"])
    }

    @Test func `Replacement writes one complete package`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest()
        try fixture.asset(Fixture.image())
        try await PackService().exportTemplate(named: "Replacement", defaults: Fixture.defaults, to: fixture.source)
        #expect(!FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("Assets").path))
        let result = try await PackService().read(from: fixture.source)
        #expect(result.name == "Replacement")
    }

    @Test func `Validation failure leaves destination unchanged`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest()
        let before = try Data(contentsOf: fixture.source.appendingPathComponent("manifest.json"))
        await #expect(throws: ValidationError.self) {
            try await PackService().exportTemplate(named: " ", defaults: Fixture.defaults, to: fixture.source)
        }
        #expect(try Data(contentsOf: fixture.source.appendingPathComponent("manifest.json")) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["Source"])
    }

    @Test func `Write failure preserves existing file`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let parent = fixture.directory.appendingPathComponent("File")
        let original = Data("preserve me".utf8)
        try original.write(to: parent)
        await #expect(throws: (any Error).self) {
            try await PackService().exportTemplate(named: "Template", defaults: Fixture.defaults,
                                                   to: parent.appendingPathComponent("Child"))
        }
        #expect(try Data(contentsOf: parent) == original)
    }
}
