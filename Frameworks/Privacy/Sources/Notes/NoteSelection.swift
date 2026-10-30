/// The choice of the notes that a spend consumes.
enum NoteSelection {
    static let maximumNotes = 40

    /// Chooses the notes that cover an amount.
    ///
    /// - Parameters:
    ///   - lamports: The amount to cover.
    ///   - notes: The unspent notes.
    /// - Returns: The chosen notes of one tree, largest first.
    /// - Throws: ``PrivateSpend/ValidationError/tooManyNotes`` if the chosen tree needs more than 40 notes, or
    ///   ``PrivateSpend/ValidationError/insufficientFunds`` if no tree covers the amount.
    static func notes(covering lamports: UInt64, from notes: [ReceivedNote]) throws -> [ReceivedNote] {
        let candidates = Dictionary(grouping: notes, by: \.utxo.treeID)
            .compactMap { treeID, notes in covering(lamports, from: notes).map { (treeID: treeID, notes: $0) } }
        guard let best = candidates.min(by: { ($0.notes.count, $0.treeID) < ($1.notes.count, $1.treeID) }) else {
            throw PrivateSpend.ValidationError.insufficientFunds
        }
        guard best.notes.count <= maximumNotes else { throw PrivateSpend.ValidationError.tooManyNotes }
        return best.notes
    }

    /// Takes one tree's largest notes until they cover an amount.
    ///
    /// - Parameters:
    ///   - lamports: The amount to cover.
    ///   - notes: One tree's notes.
    /// - Returns: The taken notes, largest first, or `nil` if they don't cover the amount.
    private static func covering(_ lamports: UInt64, from notes: [ReceivedNote]) -> [ReceivedNote]? {
        let ordered = notes.enumerated().sorted { ($1.element.lamports, $0.offset) < ($0.element.lamports, $1.offset) }.map(\.element)
        var total: UInt64 = 0
        var taken: [ReceivedNote] = []
        for note in ordered where total < lamports {
            total += note.lamports
            taken.append(note)
        }
        return total >= lamports ? taken : nil
    }
}
