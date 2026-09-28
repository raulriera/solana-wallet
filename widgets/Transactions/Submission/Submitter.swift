import RPC
import Transactions

/// Submits the exact reviewed transaction with preflight enabled and no automatic retry.
nonisolated struct Submitter: TransactionSubmitting {
    /// A submission prerequisite or acknowledgment that cannot be accepted.
    enum Failure: Error, Sendable, Equatable {
        /// At least one required signature slot is still empty.
        case missingSignatures
        /// The signed message or preserved signatures differ from the reviewed transaction.
        case transactionMismatch
        /// The provider acknowledged another signature; the local transaction may still have been received.
        case responseMismatch(expectedSignature: String)
        /// No enabled provider serves the transaction's network.
        case noEnabledProviders
    }

    private let providers: [Provider]
    private let validator: any PreparationValidating
    private let transactionBuilder: any TransactionBuilding

    /// Creates submission with the same prerequisites used by signing.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for prerequisite checks.
    ///   - providers: The configured submission providers, or `nil` to submit through `rpc` alone.
    ///   - messageBuilder: The encoder that checks locally constructed transfer intent.
    ///   - transactionBuilder: The validator for all required transaction signatures.
    init(rpc: any RPC, providers: [Provider]? = nil, messageBuilder: any MessageBuilding = MessageBuilder(),
         transactionBuilder: any TransactionBuilding = TransactionBuilder()) {
        self.providers = providers ?? [Provider(rpc: rpc)]
        self.transactionBuilder = transactionBuilder
        validator = PreparationValidator(rpc: rpc, messageBuilder: messageBuilder, transactionBuilder: transactionBuilder)
    }

    /// Validates and serializes a typed signed result before sending it once.
    ///
    /// The original message and blockhash are preserved. Preflight uses confirmed
    /// commitment and the newest reviewed slot. Cancellation after dispatch doesn't
    /// revoke a transaction; its locally known signature remains the lookup identifier.
    ///
    /// - Parameter signed: The exact approved result of the signing workflow.
    /// - Returns: A receipt after the first matching acknowledgment; it owns remaining deliveries.
    /// - Throws: A prerequisite, signature, RPC, acknowledgment, or cancellation error.
    @concurrent
    func submit(_ signed: SignedTransaction) async throws -> Submission {
        try Task.checkCancellation()
        let eligible = providers.filter { $0.isEnabled && $0.rpc.network == signed.preparation.network }
        guard !eligible.isEmpty else { throw Failure.noEnabledProviders }
        let bytes = signed.transaction.serializedRepresentation
        let transaction = try transactionBuilder.validateSignatures(in: bytes)
        guard transaction == signed.transaction, transaction.message == signed.preparation.message else {
            throw Failure.transactionMismatch
        }
        guard signed.isFullySigned, let signature = transaction.signature else { throw Failure.missingSignatures }
        for (original, current) in zip(signed.preparation.transaction.signatures, transaction.signatures)
            where original.contains(where: { $0 != 0 }) {
            guard original == current else { throw Failure.transactionMismatch }
        }
        try await validator.validate(signed.preparation)
        try Task.checkCancellation()
        let broadcast = Broadcast(providers: eligible, request: SendTransaction(
            transaction: bytes, preflightCommitment: .confirmed, minContextSlot: signed.preparation.minimumSlot,
            skipsPreflight: false, maxRetries: 0
        ), signature: signature, network: signed.preparation.network)
        try await broadcast.waitForAcceptance()
        try Task.checkCancellation()
        return Submission(signature: signature, network: signed.preparation.network, broadcast: broadcast)
    }
}
