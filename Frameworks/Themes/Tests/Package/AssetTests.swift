import Darwin
import Foundation
import Testing
@testable import Themes

struct AssetTests {
    @Test func `Named pipe is rejected as an asset`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""assets":{"background":"Assets/image.png"}"#)
        let assets = fixture.source.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: false)
        try #require(mkfifo(assets.appendingPathComponent("image.png").path, 0o600) == 0)
        await #expect(throws: ValidationError.self) { try await PackService().read(from: fixture.source) }
    }

    @Test(arguments: ["public.png", "public.jpeg"])
    func `Supported images retain original bytes`(type: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = try Fixture.image(type: type)
        try fixture.asset(bytes, path: "Assets/nested/image")
        try fixture.manifest(#""assets":{"background":"Assets/nested/image"}"#)
        let pack = try await PackService().read(from: fixture.source)
        try FileManager.default.removeItem(at: fixture.source)
        #expect(pack.assets["background"]?.data == bytes)
        #expect(pack.assets["background"]?.path == "Assets/nested/image")
    }

    @Test(arguments: ["../outside.png", "/tmp/outside.png", "https://example.invalid/a.png",
                      "Assets/../outside.png", "Assets/./image.png", "Assets//image.png", "Assets/",
                      "Assets\\image.png", "Assets/\0image.png"])
    func `Unsafe paths are rejected`(path: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let encoded = try JSONSerialization.data(withJSONObject: ["assets": ["background": path]])
        let object = try #require(String(data: encoded, encoding: .utf8))
        try fixture.manifest(String(object.dropFirst().dropLast()))
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == "assets.background"
        }
    }

    @Test(arguments: ["missing", "corrupt", "truncated", "gif"])
    func `Invalid image rejects import`(kind: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""assets":{"background":"Assets/image.png"}"#)
        switch kind {
        case "corrupt": try fixture.asset(Data("not an image".utf8))
        case "truncated": try fixture.asset(Data(try Fixture.image().prefix(30)))
        case "gif": try fixture.asset(Fixture.image(type: "com.compuserve.gif"))
        default: break
        }
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            (error as? ValidationError)?.path == "Assets/image.png"
        }
    }

    @Test(arguments: ["package", "manifest.json", "Assets", "Assets/nested", "Assets/nested/image.png"])
    func `Symbolic links are rejected`(location: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.asset(Fixture.image(), path: "Assets/nested/image.png")
        try fixture.manifest(#""assets":{"background":"Assets/nested/image.png"}"#)
        let original = location == "package" ? fixture.source : fixture.source.appendingPathComponent(location)
        let moved = fixture.directory.appendingPathComponent("LinkedContent")
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: moved)
        await #expect(throws: ValidationError.self) { try await PackService().read(from: fixture.source) }
    }
}
