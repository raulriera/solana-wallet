import ModularArithmetic
@testable import Privacy

enum NoteFixtures {
    static func note(at index: UInt8) -> ReceivedNote {
        let utxo = UTXO(
            owner: Poseidon.Element(UInt64(index) + 1), mint: [UInt8](repeating: 0, count: 32), amount: 1, blinding: Poseidon.Element(UInt64(7)),
            treeID: 0
        )
        return ReceivedNote(
            utxo: utxo, leafIndex: UInt64(index), signature: IndexerResponses.signature(index + 100), slot: UInt64(index),
            nullifier: Poseidon.Element(UInt64(index) + 1_000)
        )
    }
}
