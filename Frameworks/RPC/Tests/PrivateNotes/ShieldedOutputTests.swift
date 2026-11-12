import RPC
import Testing

struct ShieldedOutputTests {
    private static let output = ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 3, leafIndex: 4, payload: [5])

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
