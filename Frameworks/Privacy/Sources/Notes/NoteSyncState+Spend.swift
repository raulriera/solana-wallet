import ModularArithmetic
public import RPC
import Transactions

extension NoteSyncState {
    /// Spends the account's notes into a private transfer, a public withdrawal, or both, and proves the spend.
    ///
    /// - Parameters:
    ///   - amount: The positive amount to transfer or withdraw, in the asset's smallest unit.
    ///   - asset: The asset to spend.
    ///   - destination: The shielded recipient, the owner of a withdrawal, or a shielded recipient that also receives
    ///     public lamports.
    ///   - account: The account of this state.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    /// - Returns: The proved spend.
    /// - Throws: ``PrivateSpend/ValidationError/noOutputTree`` before a sync reports a tree,
    ///   ``Transactions/ValidationError/invalidAmount`` for a zero or overflowing amount,
    ///   ``PrivateSpend/ValidationError/insufficientFunds`` or ``PrivateSpend/ValidationError/tooManyNotes``
    ///   if the notes can't cover the amount, or an error from the client, the prover, or a proof check.
    @concurrent
    public func spend(
        _ amount: UInt64,
        of asset: PrivateAsset,
        to destination: PrivateSpend.Destination,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding
    ) async throws -> PrivateSpend {
        var generator = SystemRandomNumberGenerator()
        return try await spend(amount, of: asset, to: destination, from: account, rpc: rpc, prover: prover, using: &generator)
    }

    /// Spends the account's notes with a source of randomness.
    ///
    /// - Parameters:
    ///   - amount: The positive amount to transfer or withdraw, in the asset's smallest unit.
    ///   - asset: The asset to spend.
    ///   - destination: The shielded recipient, the owner of a withdrawal, or a shielded recipient that also receives
    ///     public lamports.
    ///   - account: The account of this state.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    ///   - generator: The source of the padding, blindings, and salt.
    /// - Returns: The proved spend.
    /// - Throws: An error as ``spend(_:of:to:from:rpc:prover:)`` describes.
    func spend(
        _ amount: UInt64,
        of asset: PrivateAsset,
        to destination: PrivateSpend.Destination,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding,
        using generator: inout some RandomNumberGenerator
    ) async throws -> PrivateSpend {
        guard let outputTreeID else { throw PrivateSpend.ValidationError.noOutputTree }
        guard amount > 0 else { throw Transactions.ValidationError.invalidAmount }
        let (transfer, withdrawal) = try destination.parts(moving: amount, of: asset)
        guard withdrawal?.amount != 0 else { throw Transactions.ValidationError.invalidAmount }
        let (covered, overflow) = (transfer?.amount ?? 0).addingReportingOverflow(withdrawal?.amount ?? 0)
        guard !overflow else { throw Transactions.ValidationError.invalidAmount }
        let selected = try await unqueuedNotes(of: asset, covering: covered, writingTo: outputTreeID, using: rpc)
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), of: asset, sender: account, transfer: transfer, withdrawal: withdrawal, outputTreeID: outputTreeID,
            using: &generator
        )
        let sender = try account.recipient.owner
        let receivedAmount = plan.outputs.filter { $0.owner?.owner == sender }.reduce(0) { $0 + ($1.utxo?.amount ?? 0) }
        return PrivateSpend(
            openings: try destination.openings(of: asset, paidBy: account.signingAddress),
            instruction: try await plan.instruction(nullifierKey: account.nullifierKey, prover: prover),
            amount: amount, receivedAmount: receivedAmount,
            treeIDs: TransactPlan.writtenTreeIDs(inputs: plan.inputTreeIDs, output: plan.outputTreeID),
            nullifiers: selected.map(\.nullifier), asset: asset
        )
    }

    /// Selects notes of an asset that cover an amount, leaving out notes whose nullifiers the program already queued.
    ///
    /// - Parameters:
    ///   - asset: The asset of the notes.
    ///   - amount: The amount to cover, in the asset's smallest unit.
    ///   - outputTreeID: The ID of the tree that receives the spend's outputs.
    ///   - rpc: The client of the notes' network.
    /// - Returns: The selected notes, whose nullifiers aren't queued.
    /// - Throws: An error from ``NoteSelection/notes(covering:from:writingTo:)`` if the unqueued notes can't
    ///   cover the amount, or from ``ShieldedPool/queuedNullifiers(of:using:)``.
    private func unqueuedNotes(
        of asset: PrivateAsset, covering amount: UInt64, writingTo outputTreeID: UInt16, using rpc: some RPC
    ) async throws -> [ReceivedNote] {
        var available = notes(of: asset)
        while true {
            let selected = try NoteSelection.notes(covering: amount, from: available, writingTo: outputTreeID)
            let queued = try await ShieldedPool.queuedNullifiers(of: selected, using: rpc)
            guard !queued.isEmpty else { return selected }
            available.removeAll { queued.contains($0.nullifier.bigEndianBytes) }
        }
    }
}
