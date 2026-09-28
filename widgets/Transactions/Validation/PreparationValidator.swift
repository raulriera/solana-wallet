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

/// Shared validation used before signing and before submission.
nonisolated struct PreparationValidator: PreparationValidating {
    /// An operation prerequisite that requires a new preparation or user review.
    enum Failure: Error, Sendable, Equatable {
        /// The selected provider serves a different network from the reviewed preparation.
        case networkMismatch
        /// The encoded message differs from the reviewed inspection or native transfer intent.
        case messageMismatch
        /// Simulation reported that the transaction couldn't execute.
        case simulationFailed
        /// The preparation has no known network fee to review.
        case feeUnavailable
        /// The simulation, fee, or ledger contexts conflict with the prepared message.
        case inconsistentPreparation
        /// The provider can no longer confirm the reviewed total fee.
        case feeChanged
        /// The original blockhash has expired or its current validity can't be established.
        case expired
    }

    private let rpc: any RPC
    private let messageBuilder: any MessageBuilding
    private let transactionBuilder: any TransactionBuilding

    /// Creates prerequisite checks with a provider and reusable transaction validators.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for current fee and lifetime observations.
    ///   - messageBuilder: The encoder used to check native transfer intent.
    ///   - transactionBuilder: The structural and signature validator.
    init(rpc: any RPC, messageBuilder: any MessageBuilding = MessageBuilder(),
         transactionBuilder: any TransactionBuilding = TransactionBuilder()) {
        self.rpc = rpc
        self.messageBuilder = messageBuilder
        self.transactionBuilder = transactionBuilder
    }

    /// Checks the exact reviewed transaction before an operation with external effects.
    ///
    /// - Parameter preparation: The review whose metadata, lifetime, and fee to verify.
    /// - Throws: A prerequisite, RPC, or cancellation error without substituting new bytes.
    @concurrent
    func validate(_ preparation: Preparation) async throws {
        try Task.checkCancellation()
        try validateReview(preparation)
        try await validateLifetime(preparation)
        let fee = try await rpc.send(GetFeeForMessage(
            message: preparation.message, commitment: .confirmed, minContextSlot: preparation.minimumSlot
        ))
        try Task.checkCancellation()
        guard fee.context.slot >= preparation.minimumSlot,
              fee.value == preparation.fee.value else { throw Failure.feeChanged }
    }

    /// Checks that review metadata agrees with exact message bytes and any native transfer intent.
    ///
    /// - Parameter preparation: The review data to validate before signing or submission.
    /// - Throws: ``Failure`` for inconsistent or unsuccessful review data, or an encoding error.
    private func validateReview(_ preparation: Preparation) throws {
        guard preparation.network == rpc.network else { throw Failure.networkMismatch }
        guard preparation.simulation.value.error == nil else { throw Failure.simulationFailed }
        guard let fee = preparation.fee.value else { throw Failure.feeUnavailable }
        guard fee >= (preparation.transaction.requests.priorityFeeLamports ?? 0),
              preparation.simulation.value.fee.map({ $0 == fee }) ?? true,
              preparation.simulation.value.replacementBlockhash == nil,
              preparation.fee.context.slot >= preparation.source.context.slot,
              preparation.simulation.context.slot >= preparation.source.context.slot else {
            throw Failure.inconsistentPreparation
        }
        if case .transfer(let transfer, let configuration, let blockhash) = preparation.source {
            let message = try messageBuilder.message(
                for: transfer, recentBlockhash: blockhash.value.blockhash, configuration: configuration
            )
            guard message == preparation.message, preparation.signer == transfer.sender else {
                throw Failure.messageMismatch
            }
        }
        let decoded = try transactionBuilder.validateSignatures(in: preparation.bytes, for: preparation.signer)
        guard decoded == preparation.transaction else { throw Failure.messageMismatch }
    }

    /// Checks the original lifetime at the current ledger without replacing it.
    ///
    /// - Parameter preparation: The blockhash expiry and context to check.
    /// - Throws: ``Failure/expired``, an RPC error, or cancellation.
    func validateLifetime(_ preparation: Preparation) async throws {
        try Task.checkCancellation()
        switch preparation.source {
        case .transfer(_, _, let blockhash):
            let height = try await rpc.send(GetBlockHeight(
                commitment: .confirmed, minContextSlot: preparation.minimumSlot
            ))
            try Task.checkCancellation()
            guard height <= blockhash.value.lastValidBlockHeight else { throw Failure.expired }
        case .external:
            let validity = try await rpc.send(IsBlockhashValid(
                blockhash: preparation.transaction.lifetimeSpecifier,
                commitment: .confirmed, minContextSlot: preparation.minimumSlot
            ))
            try Task.checkCancellation()
            guard validity.value, validity.context.slot >= preparation.minimumSlot else { throw Failure.expired }
        }
    }
}
