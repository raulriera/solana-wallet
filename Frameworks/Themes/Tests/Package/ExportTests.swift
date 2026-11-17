import Foundation
import Testing
@testable import Themes

struct ExportTests {
    @Test func `Saved copy preserves overrides, shared assets, and identity without freezing defaults`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.asset(Fixture.image(), path: "Assets/nested/texture.png")
        try fixture.asset(Fixture.image(type: "public.jpeg"), path: "Assets/background.jpg")
        try fixture.manifest(##""tokens":{"colors":{"light":{"primary":{"srgb":"#12aB34"}}},"fontDesign":"monospaced"},"assets":{"texture":"Assets/nested/texture.png","background":"Assets/background.jpg","shared":"Assets/nested/texture.png"}"##)
        let service: any PackServicing = PackService()
        let original = try await service.read(from: fixture.source)
        try FileManager.default.removeItem(at: fixture.source)
        let destination = fixture.directory.appendingPathComponent("Renamed")
        try await service.save(original, to: destination)
        let saved = try await service.read(from: destination)
        #expect(saved.id == Fixture.id)
        #expect(saved.name == original.name)
        #expect(saved.assets == original.assets)
        let palette = Fixture.palette(.system(.systemRed))
        let different = Tokens(colors: Colors(light: palette, dark: palette), fontDesign: .rounded)
        let resolved = different.applying(saved)
        #expect(resolved == different.applying(original))
        #expect(resolved.colors.light[.background] == .system(.systemRed))
        #expect(resolved.fontDesign == .monospaced)
        let tokens = try #require(Fixture.exportedJSON(at: destination)["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: [String: String]]])
        #expect(colors == ["light": ["primary": ["srgb": "#12AB34"]]])
        #expect(tokens["fontDesign"] as? String == "monospaced")
    }

    @Test func `Template exports complete defaults with new identities`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service: any PackServicing = PackService()
        let first = fixture.directory.appendingPathComponent("First")
        let second = fixture.directory.appendingPathComponent("Second")
        try await service.exportTemplate(named: "Template", defaults: Fixture.defaults, to: first)
        try await service.exportTemplate(named: "Template", defaults: Fixture.defaults, to: second)
        async let firstPack = service.read(from: first)
        async let secondPack = service.read(from: second)
        let (a, b) = try await (firstPack, secondPack)
        #expect(a.id != b.id)
        #expect(a.name == "Template")
        #expect(a.assets.isEmpty)
        let alternate = Tokens(colors: Colors(light: Fixture.defaults.colors.dark, dark: Fixture.defaults.colors.light),
                               fontDesign: .rounded)
        #expect(alternate.applying(a) == Fixture.defaults)
        let json = try Fixture.exportedJSON(at: first)
        #expect(json["version"] as? Int == 1)
        #expect(json["formatVersion"] == nil)
        let tokens = try #require(json["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: [String: String]]])
        #expect(Set(colors.keys) == ["light", "dark"])
        for palette in colors.values {
            #expect(Set(palette.keys) == Set(Palette.Role.allCases.map(\.rawValue)))
        }
        #expect(colors["light"]?["background"] == ["system": "systemBackground"])
        #expect(tokens["fontDesign"] as? String == "serif")
    }

    @Test func `Saving keeps an omitted font design omitted`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest()
        let service = PackService()
        let destination = fixture.directory.appendingPathComponent("Saved")
        try await service.save(service.read(from: fixture.source), to: destination)
        let tokens = try #require(Fixture.exportedJSON(at: destination)["tokens"] as? [String: Any])
        #expect(tokens["fontDesign"] == nil)
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
