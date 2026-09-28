import Transactions

/// An approved V1 preparation with the selected wallet's signature added.
///
/// Signing does not submit the transaction or guarantee that it remains valid.
/// Once complete, these bytes authorize execution until expiry; do not log or persist them.
nonisolated struct SignedTransaction: Sendable {
    /// The original transaction inspection and network observations the user reviewed.
    let preparation: Preparation

    /// The reviewed message and signature slots, including unchanged cosigner signatures.
    let transaction: Transaction

    /// Whether every required signature slot contains a 64-byte signature.
    ///
    /// The signing workflow verifies these signatures; submission checks them again.
    /// A partially signed result may be returned to a requester but cannot yet be submitted.
    var isFullySigned: Bool {
        !transaction.signatures.isEmpty && transaction.signatures.allSatisfy {
            $0.count == 64 && $0.contains(where: { $0 != 0 })
        }
    }

    /// The transaction identifier, or `nil` until the fee payer signs.
    var signature: String? { transaction.signature }

    /// Creates a signed result without authenticating or validating its supplied values.
    ///
    /// - Parameters:
    ///   - preparation: The review data associated with the signed message.
    ///   - transaction: The corresponding transaction with the selected signature added.
    init(preparation: Preparation, transaction: Transaction) {
        self.preparation = preparation
        self.transaction = transaction
    }
}
