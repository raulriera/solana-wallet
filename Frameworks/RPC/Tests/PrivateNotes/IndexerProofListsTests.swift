import Foundation
import Testing
@testable import RPC

struct IndexerProofListsTests {
    private typealias Fixture = IndexerFixtures

    @Test
    func `Inclusion proofs decode every field`() throws {
        let list = try decode(MerkleProofList.self, proofs: [Fixture.merkleProof(leaf: 7), Fixture.merkleProof(leaf: 8)])

        let first = try #require(list.proofs.first)
        #expect(list.proofs.map(\.proof.leaf) == [Fixture.bytes(7), Fixture.bytes(8)])
        #expect(first.tree == Fixture.hash(9))
        #expect(first.proof == (try MerkleProof(leaf: Fixture.bytes(7), path: (0..<32).map { Fixture.bytes(0x10 + UInt8($0)) },
                                                leafIndex: 6, root: Fixture.bytes(0xbb), rootIndex: 499)))
    }

    @Test
    func `Non-inclusion proofs decode every field`() throws {
        let list = try decode(NonInclusionProofList.self, proofs: [Fixture.nonInclusionProof(leaf: 5)])

        let first = try #require(list.proofs.first)
        #expect(list.proofs.count == 1)
        #expect(first.tree == Fixture.hash(9))
        #expect(first.proof == (try NonInclusionProof(
            nullifier: Fixture.bytes(5), lowElement: Fixture.bytes(1), lowElementIndex: 3, highElement: Fixture.bytes(0xfe),
            path: (0..<40).map { Fixture.bytes(0x10 + UInt8($0)) }, root: Fixture.bytes(0xcc), rootIndex: 99
        )))
    }

    @Test(arguments: [
        IndexerFixtures.merkleProof(leaf: 7, treeType: 2),
        IndexerFixtures.merkleProof(leaf: 7, pathCount: 31),
        IndexerFixtures.merkleProof(leaf: 7, pathCount: 40),
        IndexerFixtures.merkleProof(leaf: 7, tree: "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC"),
        IndexerFixtures.merkleProof(leaf: 7).replacingOccurrences(of: IndexerFixtures.hash(0xbb), with: "0x0"),
        IndexerFixtures.merkleProof(leaf: 7).replacingOccurrences(of: #""rootIndex":499"#, with: #""rootIndex":65536"#),
        IndexerFixtures.merkleProof(leaf: 7).replacingOccurrences(of: #""leafIndex":6,"#, with: ""),
    ])
    func `Malformed inclusion proofs fail`(proof: String) {
        #expect(throws: (any Error).self) { try decode(MerkleProofList.self, proofs: [proof]) }
    }

    @Test(arguments: [
        IndexerFixtures.nonInclusionProof(leaf: 5, treeType: 1),
        IndexerFixtures.nonInclusionProof(leaf: 5, pathCount: 32),
        IndexerFixtures.nonInclusionProof(leaf: 5, tree: "1"),
        IndexerFixtures.nonInclusionProof(leaf: 5).replacingOccurrences(of: IndexerFixtures.hash(0xfe), with: "1"),
        IndexerFixtures.nonInclusionProof(leaf: 5).replacingOccurrences(of: #""lowElementIndex":3,"#, with: ""),
    ])
    func `Malformed non-inclusion proofs fail`(proof: String) {
        #expect(throws: (any Error).self) { try decode(NonInclusionProofList.self, proofs: [proof]) }
    }

    private func decode<List: Decodable>(_ type: List.Type, proofs: [String]) throws -> List {
        let json = #"{"context":{"blockTime":1,"slot":2},"proofs":[\#(proofs.joined(separator: ","))]}"#
        return try JSONDecoder().decode(List.self, from: Data(json.utf8))
    }
}
