import Foundation
import Testing
@testable import RPC

struct MerkleProofListTests {
    private typealias Fixture = IndexerFixtures

    @Test
    func `Inclusion proofs decode every field`() throws {
        let list = try Self.decode([Fixture.merkleProof(leaf: 7), Fixture.merkleProof(leaf: 8)])

        let first = try #require(list.proofs.first)
        #expect(list.proofs.map(\.proof.leaf) == [Fixture.bytes(7), Fixture.bytes(8)])
        #expect(first.tree == Fixture.bytes(9))
        #expect(first.proof == MerkleProof(leaf: Fixture.bytes(7), path: (0..<32).map { Fixture.bytes(0x10 + UInt8($0)) },
                                           leafIndex: 6, root: Fixture.bytes(0xbb), rootIndex: 499))
    }

    @Test(arguments: [
        IndexerFixtures.merkleProof(leaf: 7, treeType: 2),
        IndexerFixtures.merkleProof(leaf: 7, pathCount: 31),
        IndexerFixtures.merkleProof(leaf: 7, pathCount: 40),
        IndexerFixtures.merkleProof(leaf: 7, tree: "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC"),
        IndexerFixtures.merkleProof(leaf: 7).replacingOccurrences(of: IndexerFixtures.hash(0xbb), with: "0x0"),
        IndexerFixtures.merkleProof(leaf: 7).replacingOccurrences(of: #""rootIndex":499"#, with: #""rootIndex":65536"#),
        IndexerFixtures.merkleProof(leaf: 7).replacingOccurrences(of: #""leafIndex":6,"#, with: ""),
        IndexerFixtures.merkleProof(leaf: 7, leafIndex: -1),
    ])
    func `Malformed inclusion proofs fail`(proof: String) {
        #expect(throws: DecodingError.self) { try Self.decode([proof]) }
    }

    private static func decode(_ proofs: [String]) throws -> MerkleProofList {
        try JSONDecoder().decode(MerkleProofList.self, from: Data(MerkleProofReplies.result(proofs).utf8))
    }
}
