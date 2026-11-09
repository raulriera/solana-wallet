import ModularArithmetic
@testable import Privacy
import Testing

struct NoteSelectionTests {
    @Test
    func `Largest notes are taken first until they cover the amount`() throws {
        let notes = try Self.notes((0, [3, 10, 5, 1]))

        let selected = try NoteSelection.notes(covering: 12, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [1, 2])
    }

    @Test
    func `Equal amounts keep their order`() throws {
        let notes = try Self.notes((0, [4, 4, 4]))

        let selected = try NoteSelection.notes(covering: 5, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [0, 1])
    }

    @Test
    func `The tree that needs the fewest notes wins`() throws {
        let notes = try Self.notes((0, [4, 4, 4]), (1, [9, 2]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 3)

        #expect(selected.map(\.leafIndex) == [3, 4])
    }

    @Test
    func `Ties go to the lower tree`() throws {
        let notes = try Self.notes((2, [6, 6]), (1, [5, 5]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 3)

        #expect(selected.map(\.leafIndex) == [2, 3])
    }

    @Test
    func `Notes of two trees cover what no one tree holds`() throws {
        let notes = try Self.notes((0, [6]), (1, [6]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [0, 1])
    }

    @Test
    func `Fewer written trees win over fewer notes`() throws {
        let notes = try Self.notes((0, [4, 4, 4]), (1, [9]), (2, [9]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 3)

        #expect(selected.map(\.leafIndex) == [0, 1, 2])
    }

    @Test
    func `The two trees that need the fewest notes win`() throws {
        let notes = try Self.notes((0, [5]), (1, [3, 3]), (2, [6]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 3)

        #expect(selected.map(\.leafIndex) == [3, 0])
    }

    @Test
    func `Ties between two trees go to the lower trees`() throws {
        let notes = try Self.notes((2, [5]), (1, [5]), (0, [5]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 3)

        #expect(selected.map(\.leafIndex) == [2, 1])
    }

    @Test
    func `Two trees cover amounts that one tree needs more than 40 notes for`() throws {
        let notes = try Self.notes((0, Array(repeating: 1, count: 41)), (1, [30]))

        let selected = try NoteSelection.notes(covering: 41, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [41] + Array(0..<11))
    }

    @Test
    func `The output tree wins over a tree that needs fewer notes`() throws {
        let notes = try Self.notes((0, [4, 4, 4]), (1, [9, 2]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [0, 1, 2])
    }

    @Test
    func `Another tree wins when the output tree needs more than 40 notes`() throws {
        let notes = try Self.notes((0, Array(repeating: 1, count: 41)), (1, [50]))

        let selected = try NoteSelection.notes(covering: 41, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [41])
    }

    @Test
    func `Notes of the output tree join another tree's notes without an extra tree fee`() throws {
        let notes = try Self.notes((0, [8]), (1, [3, 3, 3, 3]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 0)

        #expect(selected.map(\.leafIndex) == [0, 1])
    }

    @Test
    func `Two trees with the output tree win over two other trees`() throws {
        let notes = try Self.notes((0, [5]), (1, [5]), (2, [5]))

        let selected = try NoteSelection.notes(covering: 10, from: notes, writingTo: 2)

        #expect(selected.map(\.leafIndex) == [0, 2])
    }

    @Test
    func `Spends take up to 40 notes`() throws {
        let notes = try Self.notes((0, Array(repeating: 1, count: 41)))

        #expect(try NoteSelection.notes(covering: 40, from: notes, writingTo: 0).count == 40)
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
        let entries = trees.flatMap { tree, amounts in amounts.map { (tree: tree, lamports: $0) } }
        return try entries.enumerated().map { leaf, note in
            ReceivedNote(
                utxo: try PlanFixtures.utxo(lamports: note.lamports, treeID: note.tree), leafIndex: UInt64(leaf),
                signature: IndexerResponses.signature(1), slot: 1, nullifier: Poseidon.Element(UInt64(leaf))
            )
        }
    }
}
