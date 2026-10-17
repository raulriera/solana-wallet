import Foundation
import Testing
@testable import RPC

/// Verifies the strict decoding of the indexer's inclusion and non-inclusion proof results.
struct IndexerProofListsTests {
    private typealias Fixture = IndexerFixtures

    /// Verifies an inclusion proof decodes its tree, leaf, 32 siblings in order, leaf index, root, and root index,
    /// ignoring the root's sequence number.
    ///
    /// - Throws: A decoding error, or a failed test prerequisite.
    @Test
    func `Inclusion proofs decode every field`() throws {
        let list = try decode(MerkleProofList.self, proofs: [Fixture.merkleProof(leaf: 7), Fixture.merkleProof(leaf: 8)])

        let first = try #require(list.proofs.first)
        #expect(list.proofs.map(\.proof.leaf) == [Fixture.bytes(7), Fixture.bytes(8)])
        #expect(first.tree == Fixture.hash(9))
        #expect(first.proof == (try MerkleProof(leaf: Fixture.bytes(7), path: (0..<32).map { Fixture.bytes(0x10 + UInt8($0)) },
                                                leafIndex: 6, root: Fixture.bytes(0xbb), rootIndex: 499)))
    }

    /// Verifies a non-inclusion proof decodes its tree, nullifier, low and high elements, low element index, 40
    /// siblings in order, root, and root index, ignoring the high element's index.
    ///
    /// - Throws: A decoding error, or a failed test prerequisite.
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

    /// Verifies inclusion proofs of another tree type or path length, or with an invalid tree or hash, fail.
    ///
    /// - Parameter proof: A malformed proof's JSON object.
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

    /// Verifies non-inclusion proofs of another tree type or path length, or with a missing or invalid element, fail.
    ///
    /// - Parameter proof: A malformed proof's JSON object.
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

    /// Decodes a result object holding proofs.
    /// - Parameters:
    ///   - type: The list type.
    ///   - proofs: The proofs' JSON objects.
    /// - Returns: The decoded list.
    /// - Throws: A decoding error.
    private func decode<List: Decodable>(_ type: List.Type, proofs: [String]) throws -> List {
        let json = #"{"context":{"blockTime":1,"slot":2},"proofs":[\#(proofs.joined(separator: ","))]}"#
        return try JSONDecoder().decode(List.self, from: Data(json.utf8))
    }
}
