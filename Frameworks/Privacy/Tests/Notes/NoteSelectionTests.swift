import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the choice of a spend's notes: largest first within one tree, the tree that needs the
/// fewest notes, the 40-note limit, and amounts that no tree covers.
///
/// Each note is identified by its leaf index.
struct NoteSelectionTests {
    /// Verifies that a tree's largest notes are taken first, only until they cover the amount.
    @Test
    func `Largest notes are taken first until they cover the amount`() throws {
        let notes = try Self.notes([3, 10, 5, 1])

        let selected = try NoteSelection.notes(covering: 12, from: notes)

        #expect(selected.map(\.leafIndex) == [1, 2])
    }

    /// Verifies that notes of equal amounts keep their order.
    @Test
    func `Equal amounts keep their order`() throws {
        let notes = try Self.notes([4, 4, 4])

        let selected = try NoteSelection.notes(covering: 5, from: notes)

        #expect(selected.map(\.leafIndex) == [0, 1])
    }

    /// Verifies that the tree that covers the amount with the fewest notes wins.
    @Test
    func `The tree that needs the fewest notes wins`() throws {
        let notes = try Self.notes([4, 4, 4], tree: 0) + Self.notes([9, 2], tree: 1, firstLeaf: 3)

        let selected = try NoteSelection.notes(covering: 10, from: notes)

        #expect(selected.map(\.leafIndex) == [3, 4])
    }

    /// Verifies that the lower tree ID wins between trees that need as many notes.
    @Test
    func `Ties go to the lower tree`() throws {
        let notes = try Self.notes([6, 6], tree: 2) + Self.notes([5, 5], tree: 1, firstLeaf: 2)

        let selected = try NoteSelection.notes(covering: 10, from: notes)

        #expect(selected.map(\.leafIndex) == [2, 3])
    }

    /// Verifies that a spend takes up to 40 notes.
    @Test
    func `Spends take up to 40 notes`() throws {
        let notes = try Self.notes(Array(repeating: 1, count: 41))

        #expect(try NoteSelection.notes(covering: 40, from: notes).count == 40)
    }

    /// Verifies that a tree that covers the amount only with more than 40 notes is rejected as too
    /// many notes rather than insufficient funds.
    @Test
    func `Spends that need more than 40 notes are rejected`() throws {
        let notes = try Self.notes(Array(repeating: 1, count: 41))

        #expect(throws: PrivateSpend.ValidationError.tooManyNotes) {
            try NoteSelection.notes(covering: 41, from: notes)
        }
    }

    /// Verifies that an amount that no single tree covers is rejected, even when the trees together
    /// would cover it.
    ///
    /// - Parameter notes: The amounts and trees of the notes.
    @Test(arguments: [[], [(1, 0), (2, 0)], [(6, 0), (6, 1)]] as [[(UInt64, UInt16)]])
    func `Uncovered amounts are rejected`(notes: [(UInt64, UInt16)]) throws {
        let notes = try notes.enumerated().map { index, note in try Self.note(note.0, tree: note.1, leaf: UInt64(index)) }

        #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try NoteSelection.notes(covering: 10, from: notes)
        }
    }

    /// Creates notes of one tree at consecutive leaves.
    ///
    /// - Parameters:
    ///   - amounts: The notes' amounts, in order.
    ///   - tree: The notes' tree.
    ///   - firstLeaf: The first note's leaf index.
    /// - Returns: The notes.
    /// - Throws: A test failure if a fixture is missing or malformed.
    private static func notes(_ amounts: [UInt64], tree: UInt16 = 0, firstLeaf: UInt64 = 0) throws -> [ReceivedNote] {
        try amounts.enumerated().map { index, lamports in try note(lamports, tree: tree, leaf: firstLeaf + UInt64(index)) }
    }

    /// Creates a note of the sender, whose nullifier is its leaf index.
    ///
    /// - Parameters:
    ///   - lamports: The note's amount.
    ///   - tree: The note's tree.
    ///   - leaf: The note's leaf index.
    /// - Returns: The note.
    /// - Throws: A test failure if a fixture is missing or malformed.
    private static func note(_ lamports: UInt64, tree: UInt16, leaf: UInt64) throws -> ReceivedNote {
        ReceivedNote(
            utxo: try PlanFixtures.utxo(lamports: lamports, treeID: tree), leafIndex: leaf, signature: IndexerResponses.signature(1), slot: 1,
            nullifier: Poseidon.Element(leaf)
        )
    }
}
