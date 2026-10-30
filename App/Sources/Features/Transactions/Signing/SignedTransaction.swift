import Transactions

/// An approved preparation with the selected account's signature added.
nonisolated struct SignedTransaction: Sendable {
    let preparation: Preparation

    let transaction: Transaction

    var isFullySigned: Bool {
        !transaction.signatures.isEmpty && transaction.signatures.allSatisfy {
            $0.count == 64 && $0.contains(where: { $0 != 0 })
        }
    }

    /// The transaction's identifier, or `nil` until the fee payer signs.
    var signature: String? { transaction.signature }

    /// Creates a signed transaction.
    ///
    /// - Parameters:
    ///   - preparation: The preparation that the person reviewed.
    ///   - transaction: The transaction with the signature added.
    init(preparation: Preparation, transaction: Transaction) {
        self.preparation = preparation
        self.transaction = transaction
    }
}
