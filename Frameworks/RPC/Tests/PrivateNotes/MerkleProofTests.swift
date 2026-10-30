import Testing
import RPC

struct MerkleProofTests {
    private static func value(_ byte: UInt8) -> [UInt8] { Array(repeating: byte, count: 32) }

    @Test
    func `Proofs of the UTXO tree's height keep their values`() throws {
        let path = (1...32).map { Self.value(UInt8($0)) }

        let proof = try MerkleProof(leaf: Self.value(0xaa), path: path, leafIndex: 9, root: Self.value(0xbb), rootIndex: 499)

        #expect(proof.path == path)
        #expect(proof.leafIndex == 9)
        #expect(proof.rootIndex == 499)
    }

    @Test(arguments: [
        (value(1), Array(repeating: value(2), count: 31), value(3)),
        (value(1), Array(repeating: value(2), count: 40), value(3)),
        ([1], Array(repeating: value(2), count: 32), value(3)),
        (value(1), Array(repeating: value(2), count: 31) + [[2]], value(3)),
        (value(1), Array(repeating: value(2), count: 32), Array(repeating: 3, count: 33)),
    ] as [([UInt8], [[UInt8]], [UInt8])])
    func `Proofs of another shape are refused`(leaf: [UInt8], path: [[UInt8]], root: [UInt8]) {
        #expect(throws: PrivateNoteError.invalidProof) {
            try MerkleProof(leaf: leaf, path: path, leafIndex: 0, root: root, rootIndex: 0)
        }
    }
}
