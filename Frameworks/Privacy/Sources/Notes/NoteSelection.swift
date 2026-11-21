import Algorithms

/// A note that a selection can choose, by its amount and its tree.
protocol SelectableNote: Equatable {
    /// The amount, in the asset's smallest unit.
    var amount: UInt64 { get }

    /// The ID of the tree that holds the note.
    var treeID: UInt16 { get }
}

extension ReceivedNote: SelectableNote {}

/// The choice of the notes that a spend consumes.
enum NoteSelection {
    /// Chooses the notes that cover an amount for the fewest tree fees.
    ///
    /// - Parameters:
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - notes: The unspent notes.
    ///   - outputTreeID: The ID of the tree that receives the spend's outputs.
    /// - Returns: The chosen notes, largest first, that cover the amount within one transaction's inputs and write
    ///   the fewest trees with the output tree; of those, the fewest notes from the fewest trees, with ties going to
    ///   the lower trees.
    /// - Throws: ``PrivateSpend/ValidationError/tooManyNotes`` if the notes cover the amount but no choice of trees
    ///   covers it within one transaction's inputs, or ``PrivateSpend/ValidationError/insufficientFunds`` if the notes
    ///   don't cover it.
    static func notes<Note: SelectableNote>(
        covering amount: UInt64,
        from notes: [Note],
        writingTo outputTreeID: UInt16
    ) throws -> [Note] {
        let candidates = treeChoices(of: notes).compactMap { covering(amount, from: $0) }
            .filter { $0.count <= TransactPlan.maximumInputs }
        let best = candidates.min { rank(of: $0, writingTo: outputTreeID) < rank(of: $1, writingTo: outputTreeID) }
        guard let best else {
            let total = notes.reduce(0) { $0 + $1.amount }
            throw total >= amount ? PrivateSpend.ValidationError.tooManyNotes : .insufficientFunds
        }
        return best
    }

    /// Lists the notes of each choice of trees that one transaction spends from.
    ///
    /// - Parameter notes: The unspent notes.
    /// - Returns: The notes of each tree and of each pair of trees, in the order of the lower trees.
    static func treeChoices<Note: SelectableNote>(of notes: [Note]) -> [[Note]] {
        let trees = Dictionary(grouping: notes, by: \.treeID).sorted { $0.key < $1.key }.map(\.value)
        return trees.combinations(ofCount: 1...TransactPlan.maximumInputTrees).map { Array($0.joined()) }
    }

    /// Ranks notes by what spending them costs.
    ///
    /// - Parameters:
    ///   - notes: The notes to spend.
    ///   - outputTreeID: The ID of the tree that receives the spend's outputs.
    /// - Returns: The number of trees that the spend writes, the number of notes, and the number of their trees.
    private static func rank(of notes: [some SelectableNote], writingTo outputTreeID: UInt16) -> (Int, Int, Int) {
        let inputTreeIDs = Set(notes.map(\.treeID))
        let writtenTreeIDs = TransactPlan.writtenTreeIDs(inputs: inputTreeIDs, output: outputTreeID)
        return (writtenTreeIDs.count, notes.count, inputTreeIDs.count)
    }

    /// Takes the largest notes until they cover an amount.
    ///
    /// - Parameters:
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - notes: The notes to take from.
    /// - Returns: The taken notes, largest first, or `nil` if they don't cover the amount.
    private static func covering<Note: SelectableNote>(_ amount: UInt64, from notes: [Note]) -> [Note]? {
        var total: UInt64 = 0
        var taken: [Note] = []
        for note in notes.sorted(by: { $0.amount > $1.amount }) where total < amount {
            total += note.amount
            taken.append(note)
        }
        return total >= amount ? taken : nil
    }
}
