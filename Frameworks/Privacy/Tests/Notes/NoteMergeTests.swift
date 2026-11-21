import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct NoteMergeTests {
    private let sender: ShieldedAccount

    init() throws {
        sender = try TransferVectors.sender()
    }

    @Test(arguments: [
        (trees: [(0, Array(repeating: 1, count: 41))], amount: 40),
        (trees: [(0, Array(repeating: 1, count: 44) + [5])], amount: 44),
        (trees: [(0, Array(repeating: 1, count: 50)), (1, Array(repeating: 2, count: 30))], amount: 70),
        (trees: [(0, [10]), (1, [3]), (2, [7])], amount: 17),
    ] as [(trees: [(UInt16, [UInt64])], amount: UInt64)])
    func `Merges total the 40 largest notes of the one or two trees that hold the most`(
        trees: [(UInt16, [UInt64])], amount: UInt64
    ) throws {
        #expect(try NoteMerge.amount(merging: NoteFixtures.notes(trees, of: .nativeSOL)) == amount)
    }

    @Test(arguments: [
        (trees: [(0, Array(repeating: 1, count: 40))], outputTreeID: 0, amount: 40, merges: 0),
        (trees: [(0, Array(repeating: 1, count: 41))], outputTreeID: 0, amount: 41, merges: 1),
        (trees: [(0, Array(repeating: 1, count: 79))], outputTreeID: 0, amount: 79, merges: 1),
        (trees: [(0, Array(repeating: 1, count: 80))], outputTreeID: 0, amount: 80, merges: 2),
        (trees: [(0, Array(repeating: 1, count: 120))], outputTreeID: 0, amount: 120, merges: 3),
        (
            trees: [(0, Array(repeating: 2, count: 50)), (1, Array(repeating: 1, count: 50))],
            outputTreeID: 0, amount: 120, merges: 1
        ),
        (
            trees: [(0, Array(repeating: 2, count: 50)), (1, Array(repeating: 1, count: 50))],
            outputTreeID: 2, amount: 120, merges: 2
        ),
        (
            trees: [
                (1, Array(repeating: 3, count: 25) + Array(repeating: 1, count: 25)),
                (2, Array(repeating: 2, count: 25)),
            ],
            outputTreeID: 0, amount: 150, merges: 2
        ),
        (
            trees: (0...2).map { ($0, Array(repeating: 10, count: 14) + Array(repeating: 1, count: 60)) },
            outputTreeID: 0, amount: 400, merges: 1
        ),
        (trees: (1...5).map { ($0, Array(repeating: 1, count: 30)) }, outputTreeID: 0, amount: 150, merges: 4),
        (trees: [(0, [4]), (1, [4]), (2, [4])], outputTreeID: 0, amount: 10, merges: 1),
        (trees: [(1, [4]), (2, [4]), (3, [4])], outputTreeID: 0, amount: 10, merges: 1),
        (trees: [(0, [4]), (1, [4]), (2, [4]), (3, [4])], outputTreeID: 0, amount: 14, merges: 2),
    ] as [(trees: [(UInt16, [UInt64])], outputTreeID: UInt16, amount: UInt64, merges: Int)])
    func `Merges count until one choice of trees covers the amount within 40 notes`(
        trees: [(UInt16, [UInt64])], outputTreeID: UInt16, amount: UInt64, merges: Int
    ) throws {
        let notes = try NoteFixtures.notes(trees, of: .nativeSOL)

        #expect(NoteMerge.count(covering: amount, from: notes, writingTo: outputTreeID) == merges)
    }

    @Test
    func `Accounts without notes have nothing to merge`() {
        #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try NoteMerge.amount(merging: [ReceivedNote]())
        }
    }

    @Test
    func `Merges transfer the 40 largest notes to the sender as one note`() async throws {
        let notes = try NoteFixtures.notes([(0, Array(repeating: 1, count: 41))], of: .nativeSOL)
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
        let transport = try NoteFixtures.spendTransport()
        var mergeGenerator = SeededGenerator(seed: 7)

        let result = try await NoteMerge(
            covering: 41, of: .nativeSOL, in: try NoteFixtures.state(notes: notes, outputTreeID: 0), from: sender,
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
        let notes = try NoteFixtures.notes([(0, [5] + Array(repeating: 1, count: 41))], of: .nativeSOL)
        let transport = try NoteFixtures.spendTransport(queued: [notes[0]])
        var generator = SeededGenerator(seed: 7)

        let result = try await NoteMerge(
            covering: 46, of: .nativeSOL, in: try NoteFixtures.state(notes: notes, outputTreeID: 0), from: sender,
            rpc: SolanaRPC.devnet(transport: transport), prover: StubProver.zolana(transport: transport),
            using: &generator
        ).spend

        #expect(result.nullifiers == notes[1...40].map(\.nullifier))
        #expect(result.amount == 40)
        #expect(result.receivedAmount == 40)
    }

    @Test
    func `Merges report one following transaction when queued notes would cover the amount`() async throws {
        let notes = try NoteFixtures.notes([(0, [10] + Array(repeating: 1, count: 41))], of: .nativeSOL)
        let transport = try NoteFixtures.spendTransport(queued: [notes[0]])
        var generator = SeededGenerator(seed: 7)

        let merge = try await NoteMerge(
            covering: 41, of: .nativeSOL, in: try NoteFixtures.state(notes: notes, outputTreeID: 0), from: sender,
            rpc: SolanaRPC.devnet(transport: transport), prover: StubProver.zolana(transport: transport),
            using: &generator
        )

        #expect(merge.following == 1)
    }
}
