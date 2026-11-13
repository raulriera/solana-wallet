import RPC
import Transactions

/// A submitter that sends a reviewed transaction once through one RPC, without retrying.
nonisolated struct Submitter: TransactionSubmitting {
    private let rpc: any RPC
    private let transactionBuilder = TransactionBuilder()

    /// Creates a submitter.
    ///
    /// - Parameter rpc: The RPC to submit through.
    init(rpc: any RPC) {
        self.rpc = rpc
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

    /// Checks a signed transaction against its review, then sends it through the RPC.
    ///
    /// - Parameters:
    ///   - signed: The signed transaction.
    ///   - signature: The fee payer's signature, which the RPC must acknowledge.
    /// - Throws: A prerequisite, signature, RPC, or cancellation error.
    private func send(_ signed: SignedTransaction, signature: String) async throws {
        try Task.checkCancellation()
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
        let acknowledged = try await rpc.send(SendTransaction(transaction: bytes,
                                                              minContextSlot: signed.preparation.minimumSlot))
        try Task.checkCancellation()
        guard acknowledged == signature else { throw SubmitterError.responseMismatch(expectedSignature: signature) }
    }
}
