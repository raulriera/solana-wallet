import Algorithms

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
    /// - Throws: ``PrivateSpend/ValidationError/tooManyNotes`` if covering the amount needs more notes than one
    ///   transaction spends, or ``PrivateSpend/ValidationError/insufficientFunds`` if the trees that one transaction
    ///   spends from don't cover it.
    static func notes(covering amount: UInt64, from notes: [ReceivedNote], writingTo outputTreeID: UInt16) throws
        -> [ReceivedNote] {
        let trees = Dictionary(grouping: notes, by: \.utxo.treeID).sorted { $0.key < $1.key }.map(\.value)
        let candidates = trees.combinations(ofCount: 1...TransactPlan.maximumInputTrees)
            .compactMap { combination in covering(amount, from: Array(combination.joined())) }
        guard !candidates.isEmpty else { throw PrivateSpend.ValidationError.insufficientFunds }
        let ranked = candidates.sorted { rank(of: $0, writingTo: outputTreeID) < rank(of: $1, writingTo: outputTreeID) }
        guard let best = ranked.first(where: { $0.count <= TransactPlan.maximumInputs }) else {
            throw PrivateSpend.ValidationError.tooManyNotes
        }
        return best
    }

    /// Ranks notes by what spending them costs.
    ///
    /// - Parameters:
    ///   - notes: The notes to spend.
    ///   - outputTreeID: The ID of the tree that receives the spend's outputs.
    /// - Returns: The number of trees that the spend writes, the number of notes, and the number of their trees.
    private static func rank(of notes: [ReceivedNote], writingTo outputTreeID: UInt16) -> (Int, Int, Int) {
        let inputTreeIDs = Set(notes.map(\.utxo.treeID))
        let writtenTreeIDs = TransactPlan.writtenTreeIDs(inputs: inputTreeIDs, output: outputTreeID)
        return (writtenTreeIDs.count, notes.count, inputTreeIDs.count)
    }

    /// Takes the largest notes until they cover an amount.
    ///
    /// - Parameters:
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - notes: The notes to take from.
    /// - Returns: The taken notes, largest first, or `nil` if they don't cover the amount.
    private static func covering(_ amount: UInt64, from notes: [ReceivedNote]) -> [ReceivedNote]? {
        var total: UInt64 = 0
        var taken: [ReceivedNote] = []
        for note in notes.sorted(by: { $0.amount > $1.amount }) where total < amount {
            total += note.amount
            taken.append(note)
        }
        return total >= amount ? taken : nil
    }
}
