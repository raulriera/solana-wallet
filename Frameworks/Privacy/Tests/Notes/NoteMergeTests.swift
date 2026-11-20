import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct NoteMergeTests {
    private static let amounts: [([(UInt16, [UInt64])], UInt64)] = [
        ([(0, Array(repeating: 1, count: 41))], 40),
        ([(0, Array(repeating: 1, count: 44) + [5])], 44),
        ([(0, Array(repeating: 1, count: 50)), (1, Array(repeating: 2, count: 30))], 70),
        ([(0, [10]), (1, [3]), (2, [7])], 17),
    ]

    private let sender: ShieldedAccount

    init() throws {
        sender = try TransferVectors.sender()
    }

    @Test(arguments: amounts)
    func `Merges total the 40 largest notes of the one or two trees that hold the most`(
        trees: [(UInt16, [UInt64])], amount: UInt64
    ) throws {
        #expect(try NoteMerge.amount(merging: notes(trees)) == amount)
    }

    @Test
    func `Accounts without notes have nothing to merge`() {
        #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try NoteMerge.amount(merging: [])
        }
    }

    @Test
    func `Merges transfer the 40 largest notes to the sender as one note`() async throws {
        let notes = try notes([(0, Array(repeating: 1, count: 41))])
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let selected = Array(notes.prefix(40))
        var planGenerator = SeededGenerator(seed: 7)
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), of: .nativeSOL, sender: sender,
            transfer: TransactPlan.Transfer(recipient: try sender.recipient, amount: 40), withdrawal: nil, outputTreeID: 0,
            using: &planGenerator
        )
        let proof = try plan.proof(from: IndexedProofs.proof(for: plan.shape))
        let context = TreeContext(
            utxoTreeRootIndex: IndexedProofs.utxoRootIndex, nullifierTreeRootIndex: IndexedProofs.nullifierRootIndex
        )
        let prover = try IndexedProofs.prover()
        let transport = StubTransport { request in
            try prover.respond(to: request) ?? IndexerResponses.spendReads(answering: request, queued: [])
        }
        var mergeGenerator = SeededGenerator(seed: 7)

        let result = try await NoteMerge.spend(
            of: .nativeSOL, in: state, from: sender, rpc: SolanaRPC.devnet(transport: transport),
            prover: StubProver.zolana(transport: transport), using: &mergeGenerator
        )

        #expect(result.instructions == [try plan.instruction(proof: proof, treeContexts: [context])])
        #expect(result.nullifiers == selected.map(\.nullifier))
        #expect(result.amount == 40)
        #expect(result.receivedAmount == 40)
    }

    private func notes(_ trees: [(tree: UInt16, amounts: [UInt64])]) throws -> [ReceivedNote] {
        let entries = trees.flatMap { tree, amounts in amounts.map { (tree: tree, amount: $0) } }
        return try entries.enumerated().map { leaf, note in
            let utxo = try PlanFixtures.utxo(amount: note.amount, treeID: note.tree, blindingByte: UInt8(leaf + 1), asset: .nativeSOL)
            return ReceivedNote(
                utxo: utxo, leafIndex: UInt64(leaf), signature: IndexerResponses.signature(1), slot: 1,
                nullifier: utxo.nullifier(using: sender.nullifierKey)
            )
        }
    }
}
