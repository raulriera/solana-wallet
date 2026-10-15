import RPC
import Transactions

/// A type that validates reviewed transaction prerequisites without accessing wallet recovery.
nonisolated protocol PreparationValidating: Sendable {
    /// Checks review consistency, original lifetime, and the current fee.
    ///
    /// - Parameter preparation: The unchanged preparation approved by the user.
    /// - Throws: A validation, RPC, or cancellation error.
    func validate(_ preparation: Preparation) async throws

    /// Rechecks the original lifetime without refreshing the transaction.
    ///
    /// - Parameter preparation: The reviewed lifetime and minimum ledger context.
    /// - Throws: An expiry, RPC, or cancellation error.
    func validateLifetime(_ preparation: Preparation) async throws
}

/// Validation the signer runs before signing, and the lifetime check it repeats after signing.
nonisolated struct PreparationValidator: PreparationValidating {
    private let rpc: any RPC
    private let messageBuilder: any MessageBuilding = MessageBuilder()
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()

    /// Creates prerequisite checks with a provider and reusable transaction validators.
    ///
    /// - Parameter rpc: The provider used for current fee and lifetime observations.
    init(rpc: any RPC) {
        self.rpc = rpc
    }

    /// Checks the exact reviewed transaction before an operation with external effects.
    ///
    /// The lifetime and fee reads run together; an expired lifetime is reported before a changed fee.
    /// - Parameter preparation: The review whose metadata, lifetime, and fee to verify.
    /// - Throws: A prerequisite, RPC, or cancellation error without substituting new bytes.
    @concurrent
    func validate(_ preparation: Preparation) async throws {
        try Task.checkCancellation()
        try validateReview(preparation)
        async let lifetime: Void = validateLifetime(preparation)
        async let currentFee = rpc.send(GetFeeForMessage(message: preparation.message,
                                                         minContextSlot: preparation.minimumSlot))
        let (_, fee) = try await (lifetime, currentFee)
        try Task.checkCancellation()
        guard fee.context.slot >= preparation.minimumSlot,
              fee.value == preparation.fee.value else { throw PreparationValidatorError.feeChanged }
    }

    /// Checks that review metadata agrees with exact message bytes and any local instruction composition.
    ///
    /// - Parameter preparation: The review data to validate before signing.
    /// - Throws: ``PreparationValidatorError`` for inconsistent or unsuccessful review data, or an encoding error.
    private func validateReview(_ preparation: Preparation) throws {
        guard preparation.network == rpc.network else { throw PreparationValidatorError.networkMismatch }
        guard preparation.simulation.value.error == nil else { throw PreparationValidatorError.simulationFailed }
        guard let fee = preparation.fee.value else { throw PreparationValidatorError.feeUnavailable }
        guard fee >= (preparation.transaction.requests.priorityFeeLamports ?? 0),
              preparation.simulation.value.fee.map({ $0 == fee }) ?? true,
              preparation.simulation.value.replacementBlockhash == nil,
              preparation.fee.context.slot >= preparation.source.context.slot,
              preparation.simulation.context.slot >= preparation.source.context.slot else {
            throw PreparationValidatorError.inconsistentPreparation
        }
        switch preparation.source {
        case .local(let instructions, let payer, let configuration, let blockhash):
            let message = try messageBuilder.message(instructions: instructions, payer: payer,
                recentBlockhash: blockhash.value.blockhash, configuration: configuration)
            guard message == preparation.message else { throw PreparationValidatorError.messageMismatch }
        case .external: break
        }
        let decoded = try transactionBuilder.validateSignatures(in: preparation.bytes, for: preparation.signer)
        guard decoded == preparation.transaction else { throw PreparationValidatorError.messageMismatch }
    }

    /// Checks the original lifetime at the current ledger without replacing it.
    ///
    /// - Parameter preparation: The blockhash expiry and context to check.
    /// - Throws: ``PreparationValidatorError/expired``, an RPC error, or cancellation.
    func validateLifetime(_ preparation: Preparation) async throws {
        try Task.checkCancellation()
        switch preparation.source {
        case .local(_, _, _, let blockhash):
            let height = try await rpc.send(GetBlockHeight(minContextSlot: preparation.minimumSlot))
            try Task.checkCancellation()
            guard height <= blockhash.value.lastValidBlockHeight else { throw PreparationValidatorError.expired }
        case .external:
            let validity = try await rpc.send(IsBlockhashValid(
                blockhash: preparation.transaction.lifetimeSpecifier, minContextSlot: preparation.minimumSlot
            ))
            try Task.checkCancellation()
            guard validity.value, validity.context.slot >= preparation.minimumSlot else { throw PreparationValidatorError.expired }
        }
    }
}
