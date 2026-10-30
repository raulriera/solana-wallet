import RPC
import Transactions

/// A submitter that sends a reviewed transaction through ordinary RPCs without retrying.
nonisolated struct Submitter: TransactionSubmitting {
    /// An error for a transaction that no RPC acknowledged.
    struct Rejection: Error, Sendable {
        let errors: [any Error]
    }

    private let rpcs: [any RPC]
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()

    /// Creates a submitter.
    ///
    /// - Parameter rpcs: The RPCs to submit through.
    init(rpcs: [any RPC]) {
        self.rpcs = rpcs
    }

    @concurrent
    func submit(_ signed: SignedTransaction) async throws -> Submission {
        guard let signature = signed.signature else { throw SubmitterError.missingSignatures }
        let receipt = Submission(signature: signature, preparation: signed.preparation)
        do {
            try await send(signed, signature: signature)
            return receipt
        } catch {
            throw DeliveryError(submission: receipt, cause: error)
        }
    }

    /// Checks a signed transaction against its review, then sends it through every RPC on its network at once.
    ///
    /// - Parameters:
    ///   - signed: The signed transaction.
    ///   - signature: The fee payer's signature, which every RPC must acknowledge.
    /// - Throws: A prerequisite, signature, ``Rejection``, or cancellation error.
    private func send(_ signed: SignedTransaction, signature: String) async throws {
        try Task.checkCancellation()
        let rpcs = rpcs.filter { $0.network == signed.preparation.network }
        guard !rpcs.isEmpty else { throw SubmitterError.noProviders }
        let bytes = signed.transaction.serializedRepresentation
        let transaction = try transactionBuilder.validateSignatures(in: bytes)
        guard transaction == signed.transaction, transaction.message == signed.preparation.message else {
            throw SubmitterError.transactionMismatch
        }
        guard signed.isFullySigned else { throw SubmitterError.missingSignatures }
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
        guard errors.count < rpcs.count else { throw Rejection(errors: errors) }
    }
}
