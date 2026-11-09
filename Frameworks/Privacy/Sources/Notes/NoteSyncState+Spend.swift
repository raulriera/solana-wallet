import ModularArithmetic
public import RPC
import Transactions

extension NoteSyncState {
    /// Spends the account's notes into a private transfer, a public withdrawal, or both, and proves the spend.
    ///
    /// - Parameters:
    ///   - lamports: The positive amount to transfer or withdraw.
    ///   - destination: The shielded recipient, the public address, or a shielded recipient that also
    ///     receives public lamports.
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
        _ lamports: UInt64,
        to destination: PrivateSpend.Destination,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding
    ) async throws -> PrivateSpend {
        var generator = SystemRandomNumberGenerator()
        return try await spend(lamports, to: destination, from: account, rpc: rpc, prover: prover, using: &generator)
    }

    /// Spends the account's notes with a source of randomness.
    ///
    /// - Parameters:
    ///   - lamports: The positive amount to transfer or withdraw.
    ///   - destination: The shielded recipient, the public address, or a shielded recipient that also
    ///     receives public lamports.
    ///   - account: The account of this state.
    ///   - rpc: The client of the account's network.
    ///   - prover: The prover of the account's network.
    ///   - generator: The source of the padding, blindings, and salt.
    /// - Returns: The proved spend.
    /// - Throws: An error as ``spend(_:to:from:rpc:prover:)`` describes.
    func spend(
        _ lamports: UInt64,
        to destination: PrivateSpend.Destination,
        from account: ShieldedAccount,
        rpc: some RPC,
        prover: some ProofProviding,
        using generator: inout some RandomNumberGenerator
    ) async throws -> PrivateSpend {
        guard let outputTreeID else { throw PrivateSpend.ValidationError.noOutputTree }
        guard lamports > 0 else { throw Transactions.ValidationError.invalidAmount }
        let (transfer, withdrawal): (TransactPlan.Transfer?, ExternalData.Withdrawal?) = switch destination {
        case .transfer(let recipient): (TransactPlan.Transfer(recipient: recipient, lamports: lamports), nil)
        case .withdrawal(let address): (nil, ExternalData.Withdrawal(recipient: address, lamports: lamports))
        case .fundedTransfer(let recipient, let publicLamports): (
            TransactPlan.Transfer(recipient: recipient, lamports: lamports),
            ExternalData.Withdrawal(recipient: recipient.signingAddress, lamports: publicLamports)
        )
        }
        guard withdrawal?.lamports != 0 else { throw Transactions.ValidationError.invalidAmount }
        let (covered, overflow) = (transfer?.lamports ?? 0).addingReportingOverflow(withdrawal?.lamports ?? 0)
        guard !overflow else { throw Transactions.ValidationError.invalidAmount }
        let selected = try await unqueuedNotes(covering: covered, writingTo: outputTreeID, using: rpc)
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), sender: account, transfer: transfer, withdrawal: withdrawal, outputTreeID: outputTreeID,
            using: &generator
        )
        let sender = try account.recipient.owner
        let receivedLamports = plan.outputs.filter { $0.owner?.owner == sender }.reduce(0) { $0 + ($1.utxo?.amount ?? 0) }
        return PrivateSpend(
            instruction: try await plan.instruction(nullifierKey: account.nullifierKey, prover: prover),
            lamports: lamports, receivedLamports: receivedLamports,
            treeIDs: TransactPlan.writtenTreeIDs(inputs: plan.inputTreeIDs, output: plan.outputTreeID),
            nullifiers: selected.map(\.nullifier)
        )
    }

    /// Selects notes that cover an amount, leaving out notes whose nullifiers the program already queued.
    ///
    /// - Parameters:
    ///   - lamports: The amount to cover.
    ///   - outputTreeID: The ID of the tree that receives the spend's outputs.
    ///   - rpc: The client of the notes' network.
    /// - Returns: The selected notes, whose nullifiers aren't queued.
    /// - Throws: An error from ``NoteSelection/notes(covering:from:writingTo:)`` if the unqueued notes can't
    ///   cover the amount, or from ``ShieldedPool/queuedNullifiers(of:using:)``.
    private func unqueuedNotes(
        covering lamports: UInt64, writingTo outputTreeID: UInt16, using rpc: some RPC
    ) async throws -> [ReceivedNote] {
        var available = notes
        while true {
            let selected = try NoteSelection.notes(covering: lamports, from: available, writingTo: outputTreeID)
            let queued = try await ShieldedPool.queuedNullifiers(of: selected, using: rpc)
            guard !queued.isEmpty else { return selected }
            available.removeAll { queued.contains($0.nullifier.bigEndianBytes) }
        }
    }
}
