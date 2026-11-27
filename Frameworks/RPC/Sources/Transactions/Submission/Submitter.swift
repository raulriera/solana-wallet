import Transactions

/// A submitter that sends a reviewed transaction once through one RPC, without retrying.
public struct Submitter: Sendable {
    private let rpc: any RPC
    private let transactionBuilder = TransactionBuilder()

    /// Creates a submitter.
    ///
    /// - Parameter rpc: The RPC to submit through.
    public init(rpc: any RPC) {
        self.rpc = rpc
    }

    /// Checks a signed transaction, then submits it once through its RPC.
    ///
    /// - Parameter signed: The signed transaction.
    /// - Returns: The transaction's pending outcome, whether or not the RPC accepted it.
    /// - Throws: A missing-signature error.
    @concurrent
    public func submit(_ signed: SignedTransaction) async throws -> TransactionOutcome {
        guard let signature = signed.signature else { throw SubmitterError.missingSignatures }
        try? await send(signed, signature: signature)
        return TransactionOutcome(signature: signature, network: signed.preparation.network,
                                  lastValidBlockHeight: signed.preparation.source.lastValidBlockHeight,
                                  status: .pending)
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
