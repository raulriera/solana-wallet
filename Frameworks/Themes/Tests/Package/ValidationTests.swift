import Foundation
import Testing
@testable import Themes

struct ValidationTests {
    @Test(arguments: [
        (#""tokens":null"#, "tokens"),
        (#""tokens":[]"#, "tokens"),
        (#""tokens":{"colors":null}"#, "tokens.colors"),
        (#""tokens":{"colors":{"light":null}}"#, "tokens.colors.light"),
        (#""tokens":{"colors":{"light":{"primary":null}}}"#, "tokens.colors.light.primary"),
        (#""tokens":{"colors":{"light":{"primary":{}}}}"#, "tokens.colors.light.primary"),
        (##""tokens":{"colors":{"light":{"primary":{"system":"label","srgb":"#123456"}}}}"##, "tokens.colors.light.primary"),
        (#""tokens":{"colors":{"light":{"primary":{"system":null}}}}"#, "tokens.colors.light.primary.system"),
        (#""tokens":{"colors":{"light":{"primary":{"system":"invented"}}}}"#, "tokens.colors.light.primary.system"),
        (#""tokens":{"colors":{"light":{"primary":{"srgb":42}}}}"#, "tokens.colors.light.primary.srgb"),
        (##""tokens":{"colors":{"light":{"primary":{"rgb":"#123456"}}}}"##, "tokens.colors.light.primary.rgb"),
        (#""tokens":{"colors":{"light":{"invented":{"system":"label"}}}}"#, "tokens.colors.light.invented"),
        (#""tokens":{"colors":{"invented":{}}}"#, "tokens.colors.invented"),
        (#""tokens":{"typography":{}}"#, "tokens.typography"),
        (#""tokens":{"fontDesign":null}"#, "tokens.fontDesign"),
        (#""tokens":{"fontDesign":1}"#, "tokens.fontDesign"),
        (#""tokens":{"fontDesign":"Menlo"}"#, "tokens.fontDesign"),
        (#""formatVersion":1"#, "formatVersion"),
        (#""assets":null"#, "assets"),
        (#""assets":{"background":null}"#, "assets.background")
    ])
    func `Invalid fields identify their path`(fields: String, path: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(fields)
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == path
        }
    }

    @Test(arguments: [
        ("{}", "version"), ("[]", "manifest.json"), ("not JSON", "manifest.json"), ("", "manifest.json"),
        (#"{"version":true}"#, "version"), (#"{"version":1.5}"#, "version"),
        (#"{"version":"1"}"#, "version"), (#"{"version":2}"#, "version"),
        (#"{"version":1}"#, "id"), (#"{"version":1,"id":"invalid"}"#, "id"),
        (#"{"version":1,"id":"\#(Fixture.id)"}"#, "name"),
        (#"{"version":1,"id":"\#(Fixture.id)","name":"  "}"#, "name")
    ])
    func `Invalid header identifies its field`(json: String, path: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.rawManifest(json)
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == path
        }
    }

    @Test(arguments: ["#123", "#123456FF", "123456", "#GG1234", "#12 345", "#１２３４５６", "#+12345"])
    func `Invalid hex is rejected`(hex: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""tokens":{"colors":{"light":{"primary":{"srgb":"\#(hex)"}}}}"#)
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == "tokens.colors.light.primary.srgb"
        }
    }

    @Test func `Remote URL is rejected`() async throws {
        let url = try #require(URL(string: "https://example.invalid/theme"))
        await #expect { try await PackService().read(from: url) } throws: { error in
            (error as? ValidationError)?.path == "package"
        }
    }
}
