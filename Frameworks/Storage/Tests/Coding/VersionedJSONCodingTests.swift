import Foundation
import Storage
import Testing

struct VersionedJSONCodingTests {
    private static let earlier = #"{"version": 1, "value": {"title": "saved"}}"#
    private static let unversioned = #"["saved"]"#

    @Test
    func `A value is kept beside the version under their permanent names`() throws {
        let coding = VersionedJSONCoding<[String]>(version: 2, unusable: .unreadable)

        let data = try coding.encode(["saved"])

        #expect(try JSONDecoder().decode(Kept.self, from: data) == Kept(version: 2, value: ["saved"]))
        #expect(coding.decode(data) == ["saved"])
    }

    @Test(arguments: [#"{"version": 3, "value": ["saved"]}"#, #"{"version": 2, "value": 7}"#, earlier, unversioned])
    func `Bytes that can't be used decode to the replacement, or to nothing without one`(_ kept: String) {
        let replacing = VersionedJSONCoding<[String]>(version: 2, unusable: .replaced(with: []))
        let failing = VersionedJSONCoding<[String]>(version: 2, unusable: .unreadable)

        #expect(replacing.decode(Data(kept.utf8)) == [])
        #expect(failing.decode(Data(kept.utf8)) == nil)
    }

    @Test(arguments: [(earlier, 1), (unversioned, 0), ("damaged", 0)])
    func `Bytes of an earlier version, or without a version, go to the migration`(kept: String, version: Int) {
        let coding = VersionedJSONCoding<[String]>(version: 2, unusable: .unreadable) { _, found in
            ["migrated from \(found)"]
        }

        #expect(coding.decode(Data(kept.utf8)) == ["migrated from \(version)"])
    }
}

private struct Kept: Decodable, Equatable {
    let version: Int
    let value: [String]
}
