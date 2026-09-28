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
        /// No supplied RPC serves the transaction's network.
        case noProviders
    }

    /// Every RPC failed to acknowledge a transaction whose delivery may remain unknown.
    struct Rejection: Error, Sendable {
        /// The locally verified identifier available for subsequent status lookup.
        let signature: String
        /// The network on which submission was attempted.
        let network: Network
        /// The independent errors returned by the RPCs, including rate-limit details.
        let errors: [any Error]
    }

    private let rpcs: [any RPC]
    private let validator: any PreparationValidating
    private let transactionBuilder: any TransactionBuilding

    /// Creates submission with the same prerequisites used by signing.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for prerequisite checks.
    ///   - rpcs: Every RPC to submit through, or `nil` to use `rpc` alone.
    ///   - messageBuilder: The encoder that checks locally constructed transfer intent.
    ///   - transactionBuilder: The validator for all required transaction signatures.
    init(rpc: any RPC, rpcs: [any RPC]? = nil, messageBuilder: any MessageBuilding = MessageBuilder(),
         transactionBuilder: any TransactionBuilding = TransactionBuilder()) {
        self.rpcs = rpcs ?? [rpc]
        self.transactionBuilder = transactionBuilder
        validator = PreparationValidator(rpc: rpc, messageBuilder: messageBuilder, transactionBuilder: transactionBuilder)
    }

    /// Validates and serializes a typed signed result before sending it once.
    ///
    /// The original message and blockhash are preserved. Preflight uses confirmed
    /// commitment and the newest reviewed slot. Cancellation after dispatch doesn't
    /// revoke a transaction; its locally known signature remains the lookup identifier.
    ///
    /// All RPC requests start concurrently. The operation finishes after the attempts
    /// settle, succeeds if any RPC acknowledges the signature, and owns all cancellation.
    ///
    /// - Parameter signed: The exact approved result of the signing workflow.
    /// - Returns: A plain receipt with the accepted signature and network.
    /// - Throws: A prerequisite, signature, RPC, acknowledgment, or cancellation error.
    @concurrent
    func submit(_ signed: SignedTransaction) async throws -> Submission {
        try Task.checkCancellation()
        let rpcs = rpcs.filter { $0.network == signed.preparation.network }
        guard !rpcs.isEmpty else { throw Failure.noProviders }
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
        let request = SendTransaction(
            transaction: bytes, preflightCommitment: .confirmed, minContextSlot: signed.preparation.minimumSlot,
            skipsPreflight: false, maxRetries: 0
        )
        let errors = await withTaskGroup(of: Result<Void, any Error>.self) { group in
            for rpc in rpcs {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let acknowledged = try await rpc.send(request)
                        try Task.checkCancellation()
                        guard acknowledged == signature else {
                            throw Failure.responseMismatch(expectedSignature: signature)
                        }
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var errors: [any Error] = []
            for await result in group {
                if case .failure(let error) = result { errors.append(error) }
            }
            return errors
        }
        try Task.checkCancellation()
        guard errors.count < rpcs.count else {
            throw Rejection(signature: signature, network: signed.preparation.network, errors: errors)
        }
        return Submission(signature: signature, network: signed.preparation.network)
    }
}
