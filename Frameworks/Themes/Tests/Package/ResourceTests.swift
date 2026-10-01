import Foundation
import Testing
@testable import Themes

struct ResourceTests {
    /// Oversized input is rejected for its resource cost before parsing or image validation.
    @Test(arguments: ["manifest.json", "Assets/image.png"])
    func oversizedFilesAreRejectedBeforeDecoding(path: String) async throws {
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
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            guard let error = error as? ValidationError else { return false }
            return error.path == path && error.reason.contains("byte limit")
        }
    }

    /// An import cannot consume the space required to export its complete resolved colors.
    @Test func manifestMustFitAfterResolvingExportDefaults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let name = String(repeating: "x", count: 1_000)
        try fixture.rawManifest(#"{"version":1,"id":"\#(Fixture.id)","name":"\#(name)"}"#)
        await #expect {
            try await FileAccess.perform(at: fixture.source) { url, access in
                try PackageFiles.read(at: url, checkCancellation: access.checkCancellation, manifestByteBudget: 1_500)
            }
        } throws: { error in
            guard let error = error as? ValidationError else { return false }
            return error.path == "manifest.json" && error.reason.contains("byte limit")
        }
    }

    /// The package budget counts unique files, accepting its boundary and rejecting another image.
    @Test func totalAssetBytesAreBoundedWithoutChargingAliasesTwice() async throws {
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
        await #expect {
            try await FileAccess.perform(at: fixture.source) { url, access in
                try PackageFiles.read(at: url, checkCancellation: access.checkCancellation, assetByteBudget: budget)
            }
        } throws: { error in
            guard let error = error as? ValidationError else { return false }
            return error.path == "Assets/extra.png" && error.reason.contains("byte limit")
        }
    }

    /// Highly compressed large images are rejected by their dimensions before thumbnail decoding.
    @Test func oversizedPixelDimensionsAreRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.asset(Fixture.image(width: 4096, height: 4097))
        try fixture.manifest(#""assets":{"background":"Assets/image.png"}"#)
        await #expect { try await PackService().read(from: fixture.source) } throws: { error in
            guard let error = error as? ValidationError else { return false }
            return error.path == "Assets/image.png" && error.reason.contains("pixel limit")
        }
    }

    /// Multiple semantic names retain one shared buffer for the same image file.
    @Test func assetAliasesShareOwnedBytes() async throws {
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
