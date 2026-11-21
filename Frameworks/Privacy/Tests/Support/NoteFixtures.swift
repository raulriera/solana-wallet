import ModularArithmetic
import RPC
@testable import Privacy

enum NoteFixtures {
    static func note(at index: UInt8) -> ReceivedNote {
        let utxo = UTXO(
            owner: Poseidon.Element(UInt64(index) + 1), asset: .nativeSOL, amount: 1,
            blinding: Poseidon.Element(UInt64(7)), treeID: 0
        )
        return ReceivedNote(
            utxo: utxo, leafIndex: UInt64(index), signature: IndexerResponses.signature(index + 100), slot: UInt64(index),
            nullifier: Poseidon.Element(UInt64(index) + 1_000)
        )
    }

    static func notes(_ trees: [(tree: UInt16, amounts: [UInt64])], of asset: PrivateAsset) throws -> [ReceivedNote] {
        let nullifierKey = try TransferVectors.sender().nullifierKey
        let entries = trees.flatMap { tree, amounts in amounts.map { (tree: tree, amount: $0) } }
        return try entries.enumerated().map { leaf, note in
            let utxo = try PlanFixtures.utxo(amount: note.amount, treeID: note.tree, blindingByte: UInt8(leaf + 1), asset: asset)
            return ReceivedNote(
                utxo: utxo, leafIndex: UInt64(leaf), signature: IndexerResponses.signature(1), slot: 1,
                nullifier: utxo.nullifier(using: nullifierKey)
            )
        }
    }

    static func state(
        position: NoteSyncPosition? = nil,
        notes: [ReceivedNote] = [],
        unconfirmedNotes: [ReceivedNote] = [],
        outputTreeID: UInt16? = nil,
        pending: [PendingAmount] = [],
        claimedSpends: Set<[UInt8]> = [],
        rejectedSpends: Set<String> = [],
        missingSpendReads: [String: Int] = [:]
    ) throws -> NoteSyncState {
        try NoteSyncState(
            position: position, notes: notes, unconfirmedNotes: unconfirmedNotes, outputTreeID: outputTreeID, pending: pending,
            localSpends: [], claimedSpends: claimedSpends, rejectedSpends: rejectedSpends, missingSpendReads: missingSpendReads
        )
    }

    static func spendTransport(queued: Set<String> = []) throws -> StubTransport {
        let prover = try IndexedProofs.prover()
        return StubTransport { request in
            try prover.respond(to: request) ?? IndexerResponses.spendReads(answering: request, queued: queued)
        }
    }
}
