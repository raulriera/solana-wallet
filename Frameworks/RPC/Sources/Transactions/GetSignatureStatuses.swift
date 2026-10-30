/// A request for the execution and confirmation statuses of transactions.
public struct GetSignatureStatuses: RPCRequest {
    public static let method = "getSignatureStatuses"

    /// The statuses in request order, with the ledger context of the lookups.
    public struct Response: Decodable, Sendable {
        public let context: Context

        /// The statuses in request order, or `nil` for a transaction that the node didn't find.
        public let value: [Status?]

        /// Creates a status result.
        ///
        /// - Parameters:
        ///   - context: The ledger context of the lookups.
        ///   - value: The statuses in request order, with `nil` for missing transactions.
        public init(context: Context, value: [Status?]) {
            self.context = context
            self.value = value
        }
    }

    /// The execution outcome and confirmation progress of a transaction.
    public struct Status: Decodable, Sendable {
        public let slot: UInt64

        /// The confirmation count, or `nil` when the transaction is rooted and finalized.
        public let confirmations: UInt64?

        /// The execution error, or `nil` if the transaction succeeded.
        public let error: TransactionError?

        /// The confirmation level, or `nil` if unavailable.
        public let confirmationStatus: Commitment?

        /// Creates a status.
        ///
        /// - Parameters:
        ///   - slot: The slot in which the transaction was processed.
        ///   - confirmations: The confirmation count, or `nil` when rooted and finalized.
        ///   - error: The execution error, or `nil` if execution succeeded.
        ///   - confirmationStatus: The confirmation level, or `nil` if unavailable.
        public init(slot: UInt64, confirmations: UInt64?, error: TransactionError?, confirmationStatus: Commitment?) {
            self.slot = slot
            self.confirmations = confirmations
            self.error = error
            self.confirmationStatus = confirmationStatus
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slot = try container.decode(UInt64.self, forKey: .slot)
            confirmations = try container.decode(UInt64?.self, forKey: .confirmations)
            error = try container.decode(TransactionError?.self, forKey: .error)
            confirmationStatus = try container.decodeIfPresent(Commitment.self, forKey: .confirmationStatus)
        }

        /// The field names in a transaction status.
        private enum CodingKeys: String, CodingKey {
            case slot, confirmations, confirmationStatus
            case error = "err"
        }
    }

    /// The base-58 transaction signatures to query.
    public let signatures: [String]

    /// Creates a request for up to 256 transaction statuses that searches the full ledger history.
    ///
    /// - Parameter signatures: Up to 256 base-58 transaction signatures.
    public init(signatures: [String]) {
        self.signatures = signatures
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(signatures)
        try parameters.encode(["searchTransactionHistory": true])
    }
}
