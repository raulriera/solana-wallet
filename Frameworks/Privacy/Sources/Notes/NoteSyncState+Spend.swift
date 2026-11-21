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
    ///   ``PrivateSpend/ValidationError/insufficientFunds`` if the notes don't cover the amount,
    ///   ``PrivateSpend/ValidationError/tooManyNotes`` if they cover it but not within one transaction, or an error
    ///   from the destination's accounts, the plan, the client, the prover, or a proof check.
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
        let parts = try destination.parts(moving: amount, of: asset, paidBy: account.signingAddress)
        let covered = try TransactPlan.spentAmount(transfer: parts.transfer, withdrawal: parts.withdrawal, of: asset)
        let selected = try await unqueuedNotes(of: asset, using: rpc) { available in
            try NoteSelection.notes(covering: covered, from: available, writingTo: outputTreeID)
        }
        return try await PrivateSpend(spending: selected, moving: amount, of: asset, parts: parts,
                                      writingTo: outputTreeID, from: account, prover: prover, using: &generator)
    }

    /// Selects notes of an asset, leaving out notes whose nullifiers the program already queued.
    ///
    /// - Parameters:
    ///   - asset: The asset of the notes.
    ///   - rpc: The client of the notes' network.
    ///   - select: Selects notes from the asset's notes that aren't known to be queued.
    /// - Returns: The selected notes, whose nullifiers aren't queued.
    /// - Throws: The selection's error, or an error from ``ShieldedPool/queuedNullifiers(of:using:)``.
    func unqueuedNotes(
        of asset: PrivateAsset, using rpc: some RPC, selecting select: ([ReceivedNote]) throws -> [ReceivedNote]
    ) async throws -> [ReceivedNote] {
        var available = notes(of: asset)
        while true {
            let selected = try select(available)
            let queued = try await ShieldedPool.queuedNullifiers(of: selected, using: rpc)
            guard !queued.isEmpty else { return selected }
            available.removeAll { queued.contains($0.nullifier.bigEndianBytes) }
        }
    }
}
