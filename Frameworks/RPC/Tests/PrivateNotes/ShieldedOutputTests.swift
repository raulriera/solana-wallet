import Testing
import RPC

/// Verifies the identity of shielded outputs.
struct ShieldedOutputTests {
    /// The output that each case changes one field of.
    private static let output = ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 3, leafIndex: 4, payload: [5])

    /// Verifies outputs are equal only when every published field is.
    ///
    /// - Parameter other: The output with one field changed.
    @Test(arguments: [
        ShieldedOutput(viewTag: [9], utxoHash: [2], treeID: 3, leafIndex: 4, payload: [5]),
        ShieldedOutput(viewTag: [1], utxoHash: [9], treeID: 3, leafIndex: 4, payload: [5]),
        ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 9, leafIndex: 4, payload: [5]),
        ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 3, leafIndex: 9, payload: [5]),
        ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 3, leafIndex: 4, payload: [9]),
    ])
    func `Outputs differ when any published field differs`(other: ShieldedOutput) {
        #expect(other != Self.output)
        #expect(ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 3, leafIndex: 4, payload: [5]) == Self.output)
    }
}
