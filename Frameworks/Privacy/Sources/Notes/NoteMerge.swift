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
    /// - Throws: ``PrivateSpend/ValidationError/insufficientFunds`` without a note of the asset, or an error from
    ///   ``NoteSyncState/spend(_:of:to:from:rpc:prover:)``.
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
        let amount = try amount(merging: state.notes(of: asset))
        return try await state.spend(amount, of: asset, to: .transfer(try account.recipient), from: account, rpc: rpc,
                                     prover: prover, using: &generator)
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
