import Foundation
import Testing
@testable import Themes

struct ValidationTests {
    @Test(arguments: [
        (#""tokens":null"#, "tokens", .invalid),
        (#""tokens":[]"#, "tokens", .invalid),
        (#""tokens":{"colors":null}"#, "tokens.colors", .invalid),
        (#""tokens":{"colors":{"light":null}}"#, "tokens.colors.light", .invalid),
        (#""tokens":{"colors":{"light":{"primary":null}}}"#, "tokens.colors.light.primary", .invalid),
        (#""tokens":{"colors":{"light":{"primary":{}}}}"#, "tokens.colors.light.primary", .invalid),
        (##""tokens":{"colors":{"light":{"primary":{"system":"label","srgb":"#123456"}}}}"##, "tokens.colors.light.primary", .invalid),
        (#""tokens":{"colors":{"light":{"primary":{"system":null}}}}"#, "tokens.colors.light.primary.system", .invalid),
        (#""tokens":{"colors":{"light":{"primary":{"system":"invented"}}}}"#, "tokens.colors.light.primary.system", .unsupported),
        (#""tokens":{"colors":{"light":{"primary":{"srgb":42}}}}"#, "tokens.colors.light.primary.srgb", .invalid),
        (#""tokens":{"fontDesign":null}"#, "tokens.fontDesign", .invalid),
        (#""tokens":{"fontDesign":1}"#, "tokens.fontDesign", .invalid),
        (#""tokens":{"fontDesign":"Menlo"}"#, "tokens.fontDesign", .unsupported),
        (#""assets":null"#, "assets", .invalid),
        (#""assets":{"background":null}"#, "assets.background", .invalid)
    ] as [(String, String, ValidationError.Kind)])
    func `Invalid fields identify their path and kind`(fields: String, path: String, kind: ValidationError.Kind) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(fields)
        await #expect(throws: ValidationError(path: path, kind: kind)) {
            try await PackService().read(from: fixture.source)
        }
    }

    @Test(arguments: [
        ("{}", "version", .invalid), ("[]", "manifest.json", .invalid), ("not JSON", "manifest.json", .invalid),
        ("", "manifest.json", .invalid), (#"{"version":true}"#, "version", .invalid),
        (#"{"version":1.5}"#, "version", .invalid), (#"{"version":"1"}"#, "version", .invalid),
        (#"{"version":2}"#, "version", .unsupported), (#"{"version":1}"#, "id", .invalid),
        (#"{"version":1,"id":"invalid"}"#, "id", .invalid),
        (#"{"version":1,"id":"\#(Fixture.id)"}"#, "name", .invalid),
        (#"{"version":1,"id":"\#(Fixture.id)","name":"  "}"#, "name", .invalid)
    ] as [(String, String, ValidationError.Kind)])
    func `Invalid header identifies its field and kind`(json: String, path: String, kind: ValidationError.Kind) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.rawManifest(json)
        await #expect(throws: ValidationError(path: path, kind: kind)) {
            try await PackService().read(from: fixture.source)
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
