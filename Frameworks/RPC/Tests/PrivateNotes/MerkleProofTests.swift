import Testing
import RPC

/// Verifies the length checks of inclusion proofs.
struct MerkleProofTests {
    /// A 32-byte value whose bytes all equal `byte`.
    /// - Parameter byte: The repeated byte.
    /// - Returns: The value.
    private static func value(_ byte: UInt8) -> [UInt8] { Array(repeating: byte, count: 32) }

    /// Verifies a proof with a 32-byte leaf, root, and 32 siblings keeps its values.
    ///
    /// - Throws: A validation error, which these lengths don't produce.
    @Test
    func `Proofs of the UTXO tree's height keep their values`() throws {
        let path = (1...32).map { Self.value(UInt8($0)) }

        let proof = try MerkleProof(leaf: Self.value(0xaa), path: path, leafIndex: 9, root: Self.value(0xbb), rootIndex: 499)

        #expect(MerkleProof.height == 32)
        #expect(proof.path == path)
        #expect(proof.leafIndex == 9)
        #expect(proof.rootIndex == 499)
    }

    /// Verifies a proof with a path of another height, or a value of another length, is refused.
    ///
    /// - Parameters:
    ///   - leaf: The leaf.
    ///   - path: The siblings.
    ///   - root: The root.
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
