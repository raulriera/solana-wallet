import Foundation
import Testing
@testable import Themes

struct ResourceTests {
    @Test(arguments: ["manifest.json", "Assets/image.png"])
    func `Oversized files are rejected before decoding`(path: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(path == "manifest.json" ? "" : #""assets":{"background":"Assets/image.png"}"#)
        let limit = path == "manifest.json" ? 1_048_576 : 16_777_216
        if path == "manifest.json" {
            let url = fixture.source.appendingPathComponent(path)
            var bytes = try Data(contentsOf: url)
            bytes.append(Data(repeating: 0x20, count: limit + 1 - bytes.count))
            try bytes.write(to: url)
        } else {
            try fixture.asset(Data())
            let handle = try FileHandle(forWritingTo: fixture.source.appendingPathComponent(path))
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(limit + 1))
        }
        await #expect(throws: ValidationError(path: path, kind: .tooLarge)) {
            try await PackService().read(from: fixture.source)
        }
    }

    @Test func `Manifest must fit after resolving export defaults`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let name = String(repeating: "x", count: 1_000)
        try fixture.rawManifest(#"{"version":1,"id":"\#(Fixture.id)","name":"\#(name)"}"#)
        await #expect(throws: ValidationError(path: "manifest.json", kind: .tooLarge)) {
            try await FileAccess.perform(at: fixture.source) { url, access in
                try PackageFiles.read(at: url, checkCancellation: access.checkCancellation, manifestByteBudget: 1_500)
            }
        }
    }

    @Test func `Total asset bytes are bounded without charging aliases twice`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = try Fixture.image()
        for index in 0..<4 { try fixture.asset(bytes, path: "Assets/\(index).png") }
        let declarations = (0..<4).map { #""\#($0)":"Assets/\#($0).png""# }.joined(separator: ",")
        try fixture.manifest(#""assets":{\#(declarations),"alias":"Assets/0.png"}"#)
        let budget = bytes.count * 4
        let count = try await FileAccess.perform(at: fixture.source) { url, access in
            try PackageFiles.read(at: url, checkCancellation: access.checkCancellation, assetByteBudget: budget).assets.count
        }
        #expect(count == 5)
        try fixture.asset(Fixture.image(), path: "Assets/extra.png")
        try fixture.manifest(#""assets":{\#(declarations),"extra":"Assets/extra.png"}"#)
        await #expect(throws: ValidationError(path: "Assets/extra.png", kind: .tooLarge)) {
            try await FileAccess.perform(at: fixture.source) { url, access in
                try PackageFiles.read(at: url, checkCancellation: access.checkCancellation, assetByteBudget: budget)
            }
        }
    }

    @Test func `Oversized pixel dimensions are rejected`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.asset(Fixture.image(width: 4096, height: 4097))
        try fixture.manifest(#""assets":{"background":"Assets/image.png"}"#)
        await #expect(throws: ValidationError(path: "Assets/image.png", kind: .tooLarge)) {
            try await PackService().read(from: fixture.source)
        }
    }

    @Test func `Asset aliases share owned bytes`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.asset(Fixture.image())
        try fixture.manifest(#""assets":{"first":"Assets/image.png","second":"Assets/image.png"}"#)
        let pack = try await PackService().read(from: fixture.source)
        let first = try #require(pack.assets["first"])
        let second = try #require(pack.assets["second"])
        let shared = first.data.withUnsafeBytes { a in
            second.data.withUnsafeBytes { b in a.baseAddress == b.baseAddress }
        }
        #expect(shared)
        try FileManager.default.removeItem(at: fixture.source)
        #expect(first.data == second.data)
    }
}
