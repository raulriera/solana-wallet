import ModularArithmetic
import Testing
@testable import Privacy

struct NoteSelectionTests {
    private static let selections: [([(UInt16, [UInt64])], UInt64, UInt16, [UInt64])] = [
        ([(0, [3, 10, 5, 1])], 12, 0, [1, 2]),
        ([(0, [4, 4, 4])], 5, 0, [0, 1]),
        ([(0, [4, 4, 4]), (1, [9, 2])], 10, 3, [3, 4]),
        ([(2, [6, 6]), (1, [5, 5])], 10, 3, [2, 3]),
        ([(0, [6]), (1, [6])], 10, 0, [0, 1]),
        ([(0, [4, 4, 4]), (1, [9]), (2, [9])], 10, 3, [0, 1, 2]),
        ([(0, [5]), (1, [3, 3]), (2, [6])], 10, 3, [3, 0]),
        ([(0, Array(repeating: 1, count: 41)), (1, [30])], 41, 0, [41] + Array(0..<11)),
        ([(0, [4, 4, 4]), (1, [9, 2])], 10, 0, [0, 1, 2]),
        ([(0, [8]), (1, [3, 3, 3, 3])], 10, 0, [0, 1]),
        ([(0, [5]), (1, [5]), (2, [5])], 10, 2, [0, 2]),
        ([(0, Array(repeating: 1, count: 41))], 40, 0, Array(0..<40)),
    ]

    @Test(arguments: selections)
    func `Selections cover the amount with the fewest written trees, then the fewest and largest notes`(
        trees: [(UInt16, [UInt64])], amount: UInt64, outputTreeID: UInt16, leafIndexes: [UInt64]
    ) throws {
        let notes = try Self.notes(trees)

        let selected = try NoteSelection.notes(covering: amount, from: notes, writingTo: outputTreeID)

        #expect(selected.map(\.leafIndex) == leafIndexes)
    }

    @Test
    func `Spends that need more than 40 notes are rejected`() throws {
        let notes = try Self.notes((0, Array(repeating: 1, count: 41)))

        #expect(throws: PrivateSpend.ValidationError.tooManyNotes) {
            try NoteSelection.notes(covering: 41, from: notes, writingTo: 0)
        }
    }

    @Test(arguments: [[], [(0, [1, 2])], [(0, [4]), (1, [4]), (2, [4])]] as [[(UInt16, [UInt64])]])
    func `Uncovered amounts are rejected`(trees: [(UInt16, [UInt64])]) throws {
        let notes = try Self.notes(trees)

        #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try NoteSelection.notes(covering: 10, from: notes, writingTo: 0)
        }
    }

    private static func notes(_ trees: (tree: UInt16, amounts: [UInt64])...) throws -> [ReceivedNote] {
        try notes(trees)
    }

    private static func notes(_ trees: [(tree: UInt16, amounts: [UInt64])]) throws -> [ReceivedNote] {
        let entries = trees.flatMap { tree, amounts in amounts.map { (tree: tree, amount: $0) } }
        return try entries.enumerated().map { leaf, note in
            ReceivedNote(
                utxo: try PlanFixtures.utxo(amount: note.amount, treeID: note.tree, asset: .nativeSOL), leafIndex: UInt64(leaf),
                signature: IndexerResponses.signature(1), slot: 1, nullifier: Poseidon.Element(UInt64(leaf))
            )
        }
    }
}
