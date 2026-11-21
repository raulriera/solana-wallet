public import RPC

/// A merge of an account's notes into one note of the account, so that a later spend needs fewer notes.
public enum NoteMerge {
    /// Merges the largest total of an asset's notes that one transaction spends into one note, and proves the merge.
    ///
    /// - Parameters:
    ///   - asset: The asset to merge.
    ///   - state: The account's notes.
    ///   - account: The account of the notes.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    /// - Returns: The proved merge, a transfer of the merged notes' total to the account's own shielded address.
    /// - Throws: ``PrivateSpend/ValidationError/noOutputTree`` before a sync reports a tree,
    ///   ``PrivateSpend/ValidationError/insufficientFunds`` without a note of the asset whose nullifier isn't queued,
    ///   or an error from the client, the prover, or a proof check.
    @concurrent
    public static func spend(
        of asset: PrivateAsset,
        in state: NoteSyncState,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding
    ) async throws -> PrivateSpend {
        var generator = SystemRandomNumberGenerator()
        return try await spend(of: asset, in: state, from: account, rpc: rpc, prover: prover, using: &generator)
    }

    /// Merges an account's notes with a source of randomness.
    ///
    /// - Parameters:
    ///   - asset: The asset to merge.
    ///   - state: The account's notes.
    ///   - account: The account of the notes.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    ///   - generator: The source of the padding, blindings, and salt.
    /// - Returns: The proved merge.
    /// - Throws: An error as ``spend(of:in:from:rpc:prover:)`` describes.
    static func spend(
        of asset: PrivateAsset,
        in state: NoteSyncState,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding,
        using generator: inout some RandomNumberGenerator
    ) async throws -> PrivateSpend {
        guard let outputTreeID = state.outputTreeID else { throw PrivateSpend.ValidationError.noOutputTree }
        let notes = try await state.unqueuedNotes(of: asset, using: rpc) { available in
            try NoteSelection.notes(covering: try amount(merging: available), from: available, writingTo: outputTreeID)
        }
        let amount = notes.reduce(0) { $0 + $1.amount }
        let transfer = TransactPlan.Transfer(recipient: try account.recipient, amount: amount)
        return try await state.spend(notes, moving: amount, of: asset, transfer: transfer, withdrawal: nil,
                                     openings: [], writingTo: outputTreeID, from: account, prover: prover,
                                     using: &generator)
    }

    /// Returns the number of merges that an account needs before one transaction covers an amount of an asset.
    ///
    /// - Parameters:
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - asset: The asset to cover the amount with.
    ///   - state: The account's notes.
    /// - Returns: The number of merges, which is zero if one transaction's inputs cover the amount. The count takes
    ///   the largest notes first and doesn't consider their trees.
    public static func count(covering amount: UInt64, of asset: PrivateAsset, in state: NoteSyncState) -> Int {
        count(covering: amount, with: state.notes(of: asset))
    }

    /// Returns the number of merges that notes need before one transaction covers an amount.
    ///
    /// - Parameters:
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - notes: The unspent notes of one asset.
    /// - Returns: The number of merges, where each merge turns one transaction's inputs into one note.
    static func count(covering amount: UInt64, with notes: [ReceivedNote]) -> Int {
        var total: UInt64 = 0
        let needed = notes.map(\.amount).sorted(by: >).prefix { note in
            defer { total += note }
            return total < amount
        }.count
        let inputs = TransactPlan.maximumInputs
        return needed <= inputs ? 0 : 1 + (needed - inputs - 1) / (inputs - 1)
    }

    /// Returns the most that one transaction spends from notes, which is the amount of one merge.
    ///
    /// - Parameter notes: The unspent notes of one asset.
    /// - Returns: The total of the largest notes, up to one transaction's inputs, of the one or two trees whose
    ///   largest notes total the most, in the asset's smallest unit.
    /// - Throws: ``PrivateSpend/ValidationError/insufficientFunds`` without a note.
    static func amount(merging notes: [ReceivedNote]) throws -> UInt64 {
        let amounts = NoteSelection.treeChoices(of: notes).map { choice in
            choice.map(\.amount).sorted(by: >).prefix(TransactPlan.maximumInputs).reduce(0, +)
        }
        guard let amount = amounts.max() else { throw PrivateSpend.ValidationError.insufficientFunds }
        return amount
    }
}
