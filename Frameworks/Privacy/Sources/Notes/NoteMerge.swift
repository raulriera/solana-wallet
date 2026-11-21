public import RPC

/// A merge of an account's notes into one note of the account, so that a later spend needs fewer notes.
public struct NoteMerge: Sendable {
    /// The proved merge, a transfer of the merged notes' total to the account's own shielded address.
    public let spend: PrivateSpend

    /// The number of transactions that the spend of the amount still needs after the merge: the later merges and the
    /// spend itself.
    ///
    /// The number is at least 1, because the spend follows the merge even when the count, which also sees notes whose
    /// nullifiers are queued, finds that one transaction covers the amount.
    public let following: Int

    /// Merges the largest total of an asset's notes that one transaction spends into one note, proves the merge, and
    /// counts the transactions that a spend of an amount still needs after it.
    ///
    /// - Parameters:
    ///   - amount: The amount that the account wants to spend, in the asset's smallest unit.
    ///   - asset: The asset to merge.
    ///   - state: The account's notes.
    ///   - account: The account of the notes.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    /// - Throws: ``PrivateSpend/ValidationError/noOutputTree`` before a sync reports a tree,
    ///   ``PrivateSpend/ValidationError/insufficientFunds`` without a note of the asset whose nullifier isn't queued,
    ///   or an error from the client, the prover, or a proof check.
    @concurrent
    public init(
        covering amount: UInt64,
        of asset: PrivateAsset,
        in state: NoteSyncState,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding
    ) async throws {
        var generator = SystemRandomNumberGenerator()
        try await self.init(covering: amount, of: asset, in: state, from: account, rpc: rpc, prover: prover,
                            using: &generator)
    }

    /// Merges an account's notes with a source of randomness.
    ///
    /// - Parameters:
    ///   - amount: The amount that the account wants to spend, in the asset's smallest unit.
    ///   - asset: The asset to merge.
    ///   - state: The account's notes.
    ///   - account: The account of the notes.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    ///   - generator: The source of the padding, blindings, and salt.
    /// - Throws: An error as ``init(covering:of:in:from:rpc:prover:)`` describes.
    init(
        covering amount: UInt64,
        of asset: PrivateAsset,
        in state: NoteSyncState,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding,
        using generator: inout some RandomNumberGenerator
    ) async throws {
        guard let outputTreeID = state.outputTreeID else { throw PrivateSpend.ValidationError.noOutputTree }
        let notes = try await state.unqueuedNotes(of: asset, using: rpc) { available in
            try Self.notes(merging: available, writingTo: outputTreeID)
        }
        let total = notes.reduce(0) { $0 + $1.amount }
        let transfer = TransactPlan.Transfer(recipient: try account.recipient, amount: total)
        spend = try await state.spend(notes, moving: total, of: asset, transfer: transfer, withdrawal: nil,
                                      openings: [], writingTo: outputTreeID, from: account, prover: prover,
                                      using: &generator)
        following = max(1, Self.count(covering: amount, of: asset, in: state))
    }

    /// Returns the number of merges that an account needs before one transaction covers an amount of an asset.
    ///
    /// The count follows the selection of a spend and of each merge: while the notes cover the amount but no choice of
    /// trees covers it within one transaction's inputs, it merges the notes that
    /// ``init(covering:of:in:from:rpc:prover:)`` merges into one note in the output tree. It reads no nullifier, so it
    /// counts notes whose nullifiers are queued, and is an estimate for them.
    ///
    /// - Parameters:
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - asset: The asset to cover the amount with.
    ///   - state: The account's notes.
    /// - Returns: The number of merges, which is zero if one transaction's inputs cover the amount, if the notes don't
    ///   cover it, or before a sync reports a tree.
    static func count(covering amount: UInt64, of asset: PrivateAsset, in state: NoteSyncState) -> Int {
        guard let outputTreeID = state.outputTreeID else { return 0 }
        let notes = state.notes(of: asset).map { SimulatedNote(amount: $0.amount, treeID: $0.treeID) }
        return simulatedMerges(of: notes, covering: amount, writingTo: outputTreeID).count
    }

    /// Simulates the merges of notes until one transaction covers an amount.
    ///
    /// - Parameters:
    ///   - notes: The unspent notes of one asset.
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - outputTreeID: The ID of the tree that receives each merged note.
    /// - Returns: The notes after the merges, and the number of merges, which is zero if one transaction's inputs
    ///   cover the amount or if the notes don't cover it.
    static func simulatedMerges(
        of notes: [SimulatedNote],
        covering amount: UInt64,
        writingTo outputTreeID: UInt16
    ) -> (notes: [SimulatedNote], count: Int) {
        var notes = notes
        var count = 0
        while true {
            do {
                _ = try NoteSelection.notes(covering: amount, from: notes, writingTo: outputTreeID)
                return (notes, count)
            } catch PrivateSpend.ValidationError.tooManyNotes {
                guard let merged = try? Self.notes(merging: notes, writingTo: outputTreeID) else { return (notes, count) }
                notes.remove(contentsOf: merged)
                notes.append(SimulatedNote(amount: merged.reduce(0) { $0 + $1.amount }, treeID: outputTreeID))
                count += 1
            } catch {
                return (notes, count)
            }
        }
    }

    /// Chooses the notes that one merge spends.
    ///
    /// - Parameters:
    ///   - notes: The unspent notes of one asset.
    ///   - outputTreeID: The ID of the tree that receives the merged note.
    /// - Returns: The notes that cover the amount of one merge, as ``NoteSelection`` chooses them.
    /// - Throws: ``PrivateSpend/ValidationError/insufficientFunds`` without a note.
    private static func notes<Note: SelectableNote>(
        merging notes: [Note],
        writingTo outputTreeID: UInt16
    ) throws -> [Note] {
        try NoteSelection.notes(covering: try amount(merging: notes), from: notes, writingTo: outputTreeID)
    }

    /// Returns the most that one transaction spends from notes, which is the amount of one merge.
    ///
    /// - Parameter notes: The unspent notes of one asset.
    /// - Returns: The total of the largest notes, up to one transaction's inputs, of the one or two trees whose
    ///   largest notes total the most, in the asset's smallest unit.
    /// - Throws: ``PrivateSpend/ValidationError/insufficientFunds`` without a note.
    static func amount(merging notes: [some SelectableNote]) throws -> UInt64 {
        let amounts = NoteSelection.treeChoices(of: notes).map { choice in
            choice.map(\.amount).sorted(by: >).prefix(TransactPlan.maximumInputs).reduce(0, +)
        }
        guard let amount = amounts.max() else { throw PrivateSpend.ValidationError.insufficientFunds }
        return amount
    }

    /// A note that a count of merges simulates, by the amount and tree that the count reads.
    struct SimulatedNote: SelectableNote {
        let amount: UInt64

        let treeID: UInt16
    }
}

extension Array where Element: Equatable {
    /// Removes one equal element for each of the given elements.
    ///
    /// - Parameter elements: The elements to remove.
    fileprivate mutating func remove(contentsOf elements: some Sequence<Element>) {
        for element in elements {
            if let index = firstIndex(of: element) {
                remove(at: index)
            }
        }
    }
}
