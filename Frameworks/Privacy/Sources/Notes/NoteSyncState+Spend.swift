public import RPC
import Transactions

extension NoteSyncState {
    /// Spends the account's notes into a private transfer or a public withdrawal and proves the
    /// transact.
    ///
    /// The notes come from one tree, largest first, at most 40; pending amounts can't be spent. The
    /// outputs go to ``outputTreeID``: the recipient's transfer, if any, and the account's change.
    /// Padding, blindings, and the salt are random. The provider's indexer supplies the trees' proofs,
    /// and its prover receives the account's nullifier secret, which lets it link the account's spends
    /// but not spend.
    ///
    /// - Parameters:
    ///   - lamports: The positive amount to transfer or withdraw.
    ///   - destination: The recipient's shielded address or the public account.
    ///   - account: The account of this state, which signs as the fee payer.
    ///   - provider: The indexer and prover of the account's network.
    /// - Returns: The proved spend.
    /// - Throws: ``PrivateSpend/ValidationError/noOutputTree`` before a sync that reports a tree,
    ///   ``Transactions/ValidationError/invalidAmount`` for zero lamports,
    ///   ``PrivateSpend/ValidationError/insufficientFunds`` or
    ///   ``PrivateSpend/ValidationError/tooManyNotes`` if the notes can't cover the amount, or an
    ///   error from planning, the provider, or the checks of its proofs.
    @concurrent
    public func spend(
        _ lamports: UInt64,
        to destination: PrivateSpend.Destination,
        from account: ShieldedAccount,
        provider: some PrivateNoteProviding & ProofProviding
    ) async throws -> PrivateSpend {
        var generator = SystemRandomNumberGenerator()
        return try await spend(lamports, to: destination, from: account, provider: provider, using: &generator)
    }

    /// Spends the account's notes with an injected source of randomness, such as a seeded generator
    /// in tests.
    ///
    /// The plan draws its random values before the proofs are read.
    ///
    /// - Parameters:
    ///   - lamports: The positive amount to transfer or withdraw.
    ///   - destination: The recipient's shielded address or the public account.
    ///   - account: The account of this state, which signs as the fee payer.
    ///   - provider: The indexer and prover of the account's network.
    ///   - generator: The source of the padding, blindings, and salt.
    /// - Returns: The proved spend.
    /// - Throws: An error as ``spend(_:to:from:provider:)`` describes.
    func spend(
        _ lamports: UInt64,
        to destination: PrivateSpend.Destination,
        from account: ShieldedAccount,
        provider: some PrivateNoteProviding & ProofProviding,
        using generator: inout some RandomNumberGenerator
    ) async throws -> PrivateSpend {
        guard let outputTreeID else { throw PrivateSpend.ValidationError.noOutputTree }
        guard lamports > 0 else { throw Transactions.ValidationError.invalidAmount }
        let selected = try NoteSelection.notes(covering: lamports, from: notes)
        let (transfer, withdrawal): (TransactPlan.Transfer?, ExternalData.Withdrawal?) = switch destination {
        case .transfer(let recipient): (TransactPlan.Transfer(recipient: recipient, lamports: lamports), nil)
        case .withdrawal(let address): (nil, ExternalData.Withdrawal(recipient: address, lamports: lamports))
        }
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), sender: account, transfer: transfer, withdrawal: withdrawal, outputTreeID: outputTreeID,
            using: &generator
        )
        let sender = try account.recipient.owner
        let receivedLamports = plan.outputs.filter { $0.owner?.owner == sender }.reduce(0) { $0 + ($1.utxo?.amount ?? 0) }
        return PrivateSpend(
            instruction: try await plan.instruction(nullifierKey: account.nullifierKey, provider: provider), lamports: lamports,
            receivedLamports: receivedLamports, nullifiers: selected.map(\.nullifier)
        )
    }
}
