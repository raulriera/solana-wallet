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
        let notes = try NoteFixtures.notes(trees, of: .nativeSOL)

        let selected = try NoteSelection.notes(covering: amount, from: notes, writingTo: outputTreeID)

        #expect(selected.map(\.leafIndex) == leafIndexes)
    }

    @Test(arguments: [
        ([(0, Array(repeating: 1, count: 41))], 41),
        ([(0, [4]), (1, [4]), (2, [4])], 10),
        ([(0, [5]), (1, [3, 3]), (2, [6])], 17),
    ] as [([(UInt16, [UInt64])], UInt64)])
    func `Covered amounts that need more than 40 notes or 2 trees are rejected as too many notes`(
        trees: [(UInt16, [UInt64])], amount: UInt64
    ) throws {
        let notes = try NoteFixtures.notes(trees, of: .nativeSOL)

        #expect(throws: PrivateSpend.ValidationError.tooManyNotes) {
            try NoteSelection.notes(covering: amount, from: notes, writingTo: 0)
        }
    }

    @Test(arguments: [[], [(0, [1, 2])], [(0, [3]), (1, [3]), (2, [3])]] as [[(UInt16, [UInt64])]])
    func `Uncovered amounts are rejected`(trees: [(UInt16, [UInt64])]) throws {
        let notes = try NoteFixtures.notes(trees, of: .nativeSOL)

        #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try NoteSelection.notes(covering: 10, from: notes, writingTo: 0)
        }
    }
}
