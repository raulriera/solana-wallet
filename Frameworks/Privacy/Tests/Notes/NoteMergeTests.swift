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

    private static let counts: [([(UInt16, [UInt64])], UInt16, UInt64, Int)] = [
        ([(0, Array(repeating: 1, count: 40))], 0, 40, 0),
        ([(0, Array(repeating: 1, count: 41))], 0, 41, 1),
        ([(0, Array(repeating: 1, count: 79))], 0, 79, 1),
        ([(0, Array(repeating: 1, count: 80))], 0, 80, 2),
        ([(0, Array(repeating: 1, count: 120))], 0, 120, 3),
        ([(0, Array(repeating: 2, count: 50)), (1, Array(repeating: 1, count: 50))], 0, 120, 1),
        ([(0, Array(repeating: 2, count: 50)), (1, Array(repeating: 1, count: 50))], 2, 120, 2),
        (
            [
                (1, Array(repeating: 3, count: 25) + Array(repeating: 1, count: 25)),
                (2, Array(repeating: 2, count: 25)),
            ],
            0, 150, 2
        ),
        ((0...2).map { ($0, Array(repeating: 10, count: 14) + Array(repeating: 1, count: 60)) }, 0, 400, 1),
        ([(0, [4]), (1, [4]), (2, [4])], 0, 10, 1),
        ([(1, [4]), (2, [4]), (3, [4])], 0, 10, 1),
        ([(0, [4]), (1, [4]), (2, [4]), (3, [4])], 0, 14, 2),
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

    @Test(arguments: counts)
    func `Merges count until one choice of trees covers the amount within 40 notes`(
        trees: [(UInt16, [UInt64])], outputTreeID: UInt16, amount: UInt64, merges: Int
    ) throws {
        let state = try Self.state(of: notes(trees), writingTo: outputTreeID)

        #expect(NoteMerge.count(covering: amount, of: .nativeSOL, in: state) == merges)
    }

    @Test
    func `Merges of notes in many trees end with a spend that one transaction covers`() throws {
        let notes = (1...5).flatMap { tree in
            Array(repeating: NoteMerge.SimulatedNote(amount: 1, treeID: UInt16(tree)), count: 30)
        }

        let merged = NoteMerge.simulatedMerges(of: notes, covering: 150, writingTo: 0)

        #expect(merged.count == 4)
        #expect(throws: Never.self) { try NoteSelection.notes(covering: 150, from: merged.notes, writingTo: 0) }
    }

    @Test
    func `Accounts before a sync reports a tree count no merge`() throws {
        let state = try Self.state(of: notes([(0, Array(repeating: 1, count: 41))]), writingTo: nil)

        #expect(NoteMerge.count(covering: 41, of: .nativeSOL, in: state) == 0)
    }

    @Test
    func `Accounts without notes have nothing to merge`() {
        #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try NoteMerge.amount(merging: [ReceivedNote]())
        }
    }

    @Test
    func `Merges transfer the 40 largest notes to the sender as one note`() async throws {
        let notes = try notes([(0, Array(repeating: 1, count: 41))])
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
        let transport = try Self.transport()
        var mergeGenerator = SeededGenerator(seed: 7)

        let result = try await NoteMerge(
            covering: 41, of: .nativeSOL, in: try Self.state(of: notes), from: sender,
            rpc: SolanaRPC.devnet(transport: transport), prover: StubProver.zolana(transport: transport),
            using: &mergeGenerator
        ).spend

        #expect(result.instructions == [try plan.instruction(proof: proof, treeContexts: [context])])
        #expect(result.nullifiers == selected.map(\.nullifier))
        #expect(result.amount == 40)
        #expect(result.receivedAmount == 40)
    }

    @Test
    func `Merges leave out a note whose nullifier is queued and take the next largest`() async throws {
        let notes = try notes([(0, [5] + Array(repeating: 1, count: 41))])
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = try Self.transport(queued: [queued])
        var generator = SeededGenerator(seed: 7)

        let result = try await NoteMerge(
            covering: 46, of: .nativeSOL, in: try Self.state(of: notes), from: sender,
            rpc: SolanaRPC.devnet(transport: transport), prover: StubProver.zolana(transport: transport),
            using: &generator
        ).spend

        #expect(result.nullifiers == notes[1...40].map(\.nullifier))
        #expect(result.amount == 40)
        #expect(result.receivedAmount == 40)
    }

    @Test
    func `Merges report one following transaction when queued notes would cover the amount`() async throws {
        let notes = try notes([(0, [10] + Array(repeating: 1, count: 41))])
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = try Self.transport(queued: [queued])
        var generator = SeededGenerator(seed: 7)

        let merge = try await NoteMerge(
            covering: 41, of: .nativeSOL, in: try Self.state(of: notes), from: sender,
            rpc: SolanaRPC.devnet(transport: transport), prover: StubProver.zolana(transport: transport),
            using: &generator
        )

        #expect(merge.following == 1)
    }

    private static func state(
        of notes: [ReceivedNote],
        writingTo outputTreeID: UInt16? = 0
    ) throws -> NoteSyncState {
        try NoteSyncState(
            position: nil,
            notes: notes,
            unconfirmedNotes: [],
            outputTreeID: outputTreeID,
            pending: [],
            localSpends: [],
            claimedSpends: [],
            rejectedSpends: [],
            missingSpendReads: [:]
        )
    }

    private static func transport(queued: Set<String> = []) throws -> StubTransport {
        let prover = try IndexedProofs.prover()
        return StubTransport { request in
            try prover.respond(to: request) ?? IndexerResponses.spendReads(answering: request, queued: queued)
        }
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
