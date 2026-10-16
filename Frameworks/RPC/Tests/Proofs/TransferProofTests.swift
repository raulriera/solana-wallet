import Testing
import RPC

/// Verifies the identity of transfer proofs and their parts.
struct TransferProofTests {
    /// A resolved tree that each case changes one field of.
    private static let tree = TransferProof.ResolvedTree(address: "a", id: 1, utxoRoot: [2], nullifierRoot: [3],
                                                         utxoRootIndex: 4, nullifierRootIndex: 5)

    /// Creates a proof with optional changes.
    /// - Parameters:
    ///   - a: The point `a`.
    ///   - b: The point `b`.
    ///   - digest: The proving key digest.
    ///   - trees: The resolved trees.
    ///   - hash: The public input hash.
    /// - Returns: The proof.
    private static func proof(a: [UInt8] = [1], b: [UInt8] = [2], digest: [UInt8] = [3],
                              trees: [TransferProof.ResolvedTree] = [tree], hash: [UInt8] = [4]) -> TransferProof {
        TransferProof(a: .init(x: a, y: [0]), b: b, c: .init(x: [5], y: [6]), provingKeyDigest: digest,
                      resolution: .init(trees: trees, publicInputHash: hash))
    }

    /// Verifies proofs are equal only when their points, digest, and resolution are.
    ///
    /// - Parameter other: The proof with one part changed.
    @Test(arguments: [proof(a: [9]), proof(b: [9]), proof(digest: [9]), proof(trees: []), proof(hash: [9])])
    func `Proofs differ when any part differs`(other: TransferProof) {
        #expect(other != Self.proof())
        #expect(Self.proof() == Self.proof())
    }

    /// Verifies resolved trees are equal only when every field is.
    ///
    /// - Parameter other: The tree with one field changed.
    @Test(arguments: [
        TransferProof.ResolvedTree(address: "b", id: 1, utxoRoot: [2], nullifierRoot: [3], utxoRootIndex: 4, nullifierRootIndex: 5),
        .init(address: "a", id: 9, utxoRoot: [2], nullifierRoot: [3], utxoRootIndex: 4, nullifierRootIndex: 5),
        .init(address: "a", id: 1, utxoRoot: [9], nullifierRoot: [3], utxoRootIndex: 4, nullifierRootIndex: 5),
        .init(address: "a", id: 1, utxoRoot: [2], nullifierRoot: [9], utxoRootIndex: 4, nullifierRootIndex: 5),
        .init(address: "a", id: 1, utxoRoot: [2], nullifierRoot: [3], utxoRootIndex: 9, nullifierRootIndex: 5),
        .init(address: "a", id: 1, utxoRoot: [2], nullifierRoot: [3], utxoRootIndex: 4, nullifierRootIndex: 9),
    ])
    func `Resolved trees differ when any field differs`(other: TransferProof.ResolvedTree) {
        #expect(other != Self.tree)
    }

    /// Verifies points are equal only when both coordinates are.
    ///
    /// - Parameter other: The point with one coordinate changed.
    @Test(arguments: [TransferProof.G1Point(x: [9], y: [2]), .init(x: [1], y: [9])])
    func `Points differ when a coordinate differs`(other: TransferProof.G1Point) {
        #expect(other != TransferProof.G1Point(x: [1], y: [2]))
    }
}
