import Foundation
import Testing
import Themes

struct ValidationTests {
    /// Malformed supplied fields report their location rather than inheriting defaults.
    @Test(arguments: [
        ("\"tokens\":null", "tokens"),
        ("\"tokens\":[]", "tokens"),
        ("\"tokens\":{\"colors\":null}", "tokens.colors"),
        ("\"tokens\":{\"colors\":{\"light\":null}}", "tokens.colors.light"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":null}}}", "tokens.colors.light.accent"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":{}}}}", "tokens.colors.light.accent"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":{\"system\":\"label\",\"srgb\":\"#123456\"}}}}", "tokens.colors.light.accent"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":{\"system\":null}}}}", "tokens.colors.light.accent.system"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":{\"system\":\"invented\"}}}}", "tokens.colors.light.accent.system"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":{\"srgb\":42}}}}", "tokens.colors.light.accent.srgb"),
        ("\"tokens\":{\"colors\":{\"light\":{\"accent\":{\"rgb\":\"#123456\"}}}}", "tokens.colors.light.accent.rgb"),
        ("\"tokens\":{\"colors\":{\"light\":{\"invented\":{\"system\":\"label\"}}}}", "tokens.colors.light.invented"),
        ("\"tokens\":{\"colors\":{\"invented\":{}}}", "tokens.colors.invented"),
        ("\"tokens\":{\"typography\":{}}", "tokens.typography"),
        ("\"formatVersion\":1", "formatVersion"),
        ("\"assets\":null", "assets"),
        ("\"assets\":{\"background\":null}", "assets.background")
    ])
    func invalidFieldsIdentifyTheirPath(fields: String, path: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(fields)
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            guard let error = error as? ValidationError else { return false }
            return error.path == path && !error.reason.isEmpty
        }
    }

    /// Invalid headers fail independently of optional appearance settings.
    @Test(arguments: [
        ("{}", "version"), ("[]", "manifest.json"), ("not JSON", "manifest.json"),
        ("{\"version\":true}", "version"), ("{\"version\":1.5}", "version"),
        ("{\"version\":\"1\"}", "version"), ("{\"version\":2}", "version"),
        ("{\"version\":1}", "id"), ("{\"version\":1,\"id\":\"invalid\"}", "id"),
        ("{\"version\":1,\"id\":\"\(Fixture.id)\"}", "name"),
        ("{\"version\":1,\"id\":\"\(Fixture.id)\",\"name\":\"  \"}", "name")
    ])
    func invalidHeaderIdentifiesItsField(json: String, path: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.rawManifest(json)
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == path
        }
    }

    /// Only opaque, six-digit hexadecimal colors are accepted.
    @Test(arguments: ["#123", "#123456FF", "123456", "#GG1234", "#12 345", "#１２３４５６", "#+12345"])
    func invalidHexIsRejected(hex: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest("\"tokens\":{\"colors\":{\"light\":{\"accent\":{\"srgb\":\"\(hex)\"}}}}")
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == "tokens.colors.light.accent.srgb"
        }
    }

    /// Package reads never treat remote locations as local files.
    @Test func remoteURLIsRejected() async throws {
        let url = try #require(URL(string: "https://example.invalid/theme"))
        await #expect { try await PackService().read(from: url) } throws: { error in
            (error as? ValidationError)?.path == "package"
        }
    }
}
