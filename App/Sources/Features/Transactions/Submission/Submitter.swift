import RPC
import Transactions

/// Submits the exact reviewed transaction with preflight enabled and no automatic retry.
nonisolated struct Submitter: TransactionSubmitting {
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
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()

    /// Creates submission through one or more ordinary RPCs.
    ///
    /// - Parameters:
    ///   - rpc: The provider to submit through when `rpcs` is `nil`.
    ///   - rpcs: Every RPC to submit through, or `nil` to use `rpc` alone.
    init(rpc: any RPC, rpcs: [any RPC]? = nil) {
        self.rpcs = rpcs ?? [rpc]
    }

    /// Checks a typed signed result against its review locally, then sends it once.
    ///
    /// Signing has just checked the review's fee and lifetime with the network and rechecked the lifetime after
    /// signing, so submission doesn't read them again. The original message and blockhash are preserved. Preflight
    /// uses finalized commitment and the newest reviewed slot. Cancellation after dispatch doesn't revoke a
    /// transaction; its locally known signature remains the lookup identifier.
    ///
    /// All RPC requests start concurrently. The operation finishes after the attempts
    /// settle, succeeds if any RPC acknowledges the signature, and owns all cancellation.
    ///
    /// - Parameter signed: The exact approved result of the signing workflow.
    /// - Returns: A plain receipt with the accepted signature, network, and blockhash expiry.
    /// - Throws: A prerequisite, signature, RPC, acknowledgment, or cancellation error.
    @concurrent
    func submit(_ signed: SignedTransaction) async throws -> Submission {
        try Task.checkCancellation()
        let rpcs = rpcs.filter { $0.network == signed.preparation.network }
        guard !rpcs.isEmpty else { throw SubmitterError.noProviders }
        let bytes = signed.transaction.serializedRepresentation
        let transaction = try transactionBuilder.validateSignatures(in: bytes)
        guard transaction == signed.transaction, transaction.message == signed.preparation.message else {
            throw SubmitterError.transactionMismatch
        }
        guard signed.isFullySigned, let signature = transaction.signature else { throw SubmitterError.missingSignatures }
        for (original, current) in zip(signed.preparation.transaction.signatures, transaction.signatures)
            where original.contains(where: { $0 != 0 }) {
            guard original == current else { throw SubmitterError.transactionMismatch }
        }
        try Task.checkCancellation()
        let request = SendTransaction(transaction: bytes, minContextSlot: signed.preparation.minimumSlot)
        let errors = await withTaskGroup(of: Result<Void, any Error>.self) { group in
            for rpc in rpcs {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let acknowledged = try await rpc.send(request)
                        try Task.checkCancellation()
                        guard acknowledged == signature else {
                            throw SubmitterError.responseMismatch(expectedSignature: signature)
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
        return Submission(signature: signature, preparation: signed.preparation)
    }
}
