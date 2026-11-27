public import Transactions

/// An approved preparation with the selected account's signature added.
public struct SignedTransaction: Sendable {
    public let preparation: Preparation

    public let transaction: Transaction

    public var isFullySigned: Bool {
        !transaction.signatures.isEmpty && transaction.signatures.allSatisfy {
            $0.count == 64 && $0.contains(where: { $0 != 0 })
        }
    }

    /// The transaction's identifier, or `nil` until the fee payer signs.
    public var signature: String? { transaction.signature }

    /// Creates a signed transaction.
    ///
    /// - Parameters:
    ///   - preparation: The preparation that the person reviewed.
    ///   - transaction: The transaction with the signature added.
    public init(preparation: Preparation, transaction: Transaction) {
        self.preparation = preparation
        self.transaction = transaction
    }
}
