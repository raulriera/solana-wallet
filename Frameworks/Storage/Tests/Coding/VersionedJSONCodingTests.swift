import Foundation
import Storage
import Testing

struct VersionedJSONCodingTests {
    private static let coding: VersionedJSONCoding<[String]> = .json([String].self, version: 2, outdated: [])

    @Test
    func `A value is kept beside the version under their permanent names`() throws {
        let data = try Self.coding.encode(["saved"])

        #expect(try JSONDecoder().decode(Kept.self, from: data) == Kept(version: 2, value: ["saved"]))
        #expect(Self.coding.decode(data) == ["saved"])
    }

    @Test(arguments: [#"{"version": 3, "value": ["saved"]}"#, #"["saved"]"#, #"{"version": 2, "value": 7}"#, "damaged"])
    func `Bytes of a later version, without a version, or damaged decode to the outdated value`(_ kept: String) {
        #expect(Self.coding.decode(Data(kept.utf8)) == [])
    }

    @Test
    func `Bytes of an earlier version that no migration reads decode to the outdated value`() {
        #expect(Self.coding.decode(Data(#"{"version": 1, "value": {"title": "saved"}}"#.utf8)) == [])
    }
}

private struct Kept: Decodable, Equatable {
    let version: Int
    let value: [String]
}
