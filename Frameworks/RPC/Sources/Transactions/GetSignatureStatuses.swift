/// A request for the current execution and confirmation status of transactions.
public struct GetSignatureStatuses: RPCRequest {
    /// The JSON-RPC method name for retrieving transaction statuses.
    public static let method = "getSignatureStatuses"

    /// Transaction statuses in request order and the ledger context in which they were read.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the status lookups.
        public let context: Context

        /// Statuses in signature order, with `nil` where the node didn't find a transaction.
        ///
        /// A missing status doesn't establish whether the transaction failed or expired.
        public let value: [Status?]

        /// Creates transaction status results with their ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the lookups.
        ///   - value: The statuses in request order, retaining `nil` for missing transactions.
        public init(context: Context, value: [Status?]) {
            self.context = context
            self.value = value
        }
    }

    /// The execution outcome and confirmation progress of a transaction found by the node.
    public struct Status: Decodable, Sendable {
        /// The slot in which the transaction was processed.
        public let slot: UInt64

        /// The confirmation count, or `nil` when the transaction is rooted and finalized.
        public let confirmations: UInt64?

        /// The execution failure, or `nil` if the transaction executed successfully.
        ///
        /// Execution failures are returned as data, independently of confirmation progress.
        public let error: TransactionError?

        /// The confirmation level reported by the node, or `nil` if unavailable.
        public let confirmationStatus: Commitment?

        /// Creates the execution outcome and confirmation progress of a transaction.
        ///
        /// - Parameters:
        ///   - slot: The slot in which the transaction was processed.
        ///   - confirmations: The confirmation count, or `nil` when rooted and finalized.
        ///   - error: The execution failure, or `nil` if execution succeeded.
        ///   - confirmationStatus: The reported confirmation level, or `nil` if unavailable.
        public init(slot: UInt64, confirmations: UInt64?, error: TransactionError?, confirmationStatus: Commitment?) {
            self.slot = slot
            self.confirmations = confirmations
            self.error = error
            self.confirmationStatus = confirmationStatus
        }

        /// Decodes a status while requiring its nullable execution and confirmation fields.
        ///
        /// - Parameter decoder: The decoder containing the transaction status.
        /// - Throws: A decoding error if a required field is missing or a field is malformed.
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

    /// The base-58 encoded transaction signatures to query, in response order.
    public let signatures: [String]

    /// Creates a request for up to 256 transaction statuses, searching ledger history beyond the recent status cache.
    ///
    /// Each call performs one lookup. Callers control polling and expiry checks.
    ///
    /// - Parameter signatures: Up to 256 base-58 encoded transaction signatures. The server validates
    ///   the signatures and their count. Split larger collections into separate requests.
    public init(signatures: [String]) {
        self.signatures = signatures
    }

    /// Encodes the signatures and the history search as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(signatures)
        try parameters.encode(["searchTransactionHistory": true])
    }
}
