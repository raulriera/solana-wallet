import RPC
import Transactions

/// A type that checks a reviewed preparation.
nonisolated protocol PreparationValidating: Sendable {
    /// Checks a preparation's consistency, blockhash lifetime, and current fee.
    ///
    /// - Parameter preparation: The approved preparation.
    /// - Throws: A validation, RPC, or cancellation error.
    func validate(_ preparation: Preparation) async throws

    /// Checks that a preparation's blockhash hasn't expired.
    ///
    /// - Parameter preparation: The approved preparation.
    /// - Throws: An expiry, RPC, or cancellation error.
    func validateLifetime(_ preparation: Preparation) async throws
}

/// A validator that checks a preparation against a provider.
nonisolated struct PreparationValidator: PreparationValidating {
    private let rpc: any RPC
    private let messageBuilder: any MessageBuilding = MessageBuilder()
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()

    /// Creates a validator.
    ///
    /// - Parameter rpc: The provider that reads the current fee and block height.
    init(rpc: any RPC) {
        self.rpc = rpc
    }

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

    /// Checks that a preparation's details match its message and any local instructions.
    ///
    /// - Parameter preparation: The preparation to check.
    /// - Throws: A ``PreparationValidatorError``, or an encoding error.
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
