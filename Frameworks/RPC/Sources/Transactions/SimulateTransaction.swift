public import Foundation

/// A request to evaluate a serialized transaction without broadcasting it.
public struct SimulateTransaction: RPCRequest {
    /// The JSON-RPC method name for transaction simulation.
    public static let method = "simulateTransaction"

    /// An execution result and the ledger context in which it was evaluated.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the simulation.
        public let context: Context

        /// The execution outcome, including any transaction failure.
        public let value: Value

        /// Creates a simulation response with its ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the simulation.
        ///   - value: The execution outcome.
        public init(context: Context, value: Value) {
            self.context = context
            self.value = value
        }
    }

    /// The outcome of evaluating a transaction, including diagnostics for failed execution.
    public struct Value: Decodable, Sendable, Equatable {
        /// The transaction failure, or `nil` if execution succeeded.
        ///
        /// Execution failures are returned with the simulation's diagnostics.
        /// Failures to perform the RPC request are thrown by the client.
        public let error: TransactionError?

        /// The program logs, or `nil` if logs weren't available.
        public let logs: [String]?

        /// The compute units consumed, or `nil` if unavailable.
        public let unitsConsumed: UInt64?

        /// The account-data bytes loaded during execution, or `nil` if unavailable.
        public let loadedAccountsDataSize: UInt32?

        /// The simulated fee in lamports, or `nil` if unavailable.
        public let fee: UInt64?

        /// The replacement blockhash and its expiry height, if supplied by the node.
        public let replacementBlockhash: GetLatestBlockhash.Value?

        /// Creates an execution outcome with its available diagnostics.
        ///
        /// - Parameters:
        ///   - error: The transaction failure, or `nil` if execution succeeded.
        ///   - logs: The program logs, or `nil` if unavailable.
        ///   - unitsConsumed: The consumed compute units, or `nil` if unavailable.
        ///   - loadedAccountsDataSize: The loaded account-data bytes, or `nil` if unavailable.
        ///   - fee: The simulated fee in lamports, or `nil` if unavailable.
        ///   - replacementBlockhash: The replacement blockhash, or `nil` if none was supplied.
        public init(
            error: TransactionError?,
            logs: [String]?,
            unitsConsumed: UInt64?,
            loadedAccountsDataSize: UInt32?,
            fee: UInt64?,
            replacementBlockhash: GetLatestBlockhash.Value?
        ) {
            self.error = error
            self.logs = logs
            self.unitsConsumed = unitsConsumed
            self.loadedAccountsDataSize = loadedAccountsDataSize
            self.fee = fee
            self.replacementBlockhash = replacementBlockhash
        }

        /// Decodes a required nullable execution error and the available diagnostics.
        ///
        /// - Parameter decoder: The decoder containing the execution outcome.
        /// - Throws: A decoding error if the error field is missing or a field is malformed.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try container.decode(TransactionError?.self, forKey: .error)
            logs = try container.decodeIfPresent([String].self, forKey: .logs)
            unitsConsumed = try container.decodeIfPresent(UInt64.self, forKey: .unitsConsumed)
            loadedAccountsDataSize = try container.decodeIfPresent(UInt32.self, forKey: .loadedAccountsDataSize)
            fee = try container.decodeIfPresent(UInt64.self, forKey: .fee)
            replacementBlockhash = try container.decodeIfPresent(GetLatestBlockhash.Value.self, forKey: .replacementBlockhash)
        }

        /// The field names in the execution result.
        private enum CodingKeys: String, CodingKey {
            case error = "err"
            case logs, unitsConsumed, loadedAccountsDataSize, fee, replacementBlockhash
        }
    }

    /// The complete serialized transaction bytes, including its signature slots.
    public let transaction: Data

    /// The confirmation level at which to simulate the transaction.
    public let commitment: Commitment

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Whether the node should verify the transaction's signatures before execution.
    public let verifiesSignatures: Bool

    /// Whether the node should substitute a recent blockhash before execution.
    public let replacesRecentBlockhash: Bool

    /// Creates a simulation request for a complete serialized transaction.
    ///
    /// The transaction may contain placeholder signatures unless verification is enabled.
    /// Signature verification and blockhash replacement can't both be enabled; the server
    /// validates this combination and the transaction bytes.
    ///
    /// - Parameters:
    ///   - transaction: The complete serialized transaction, including its signature slots.
    ///   - commitment: The confirmation level to query. The default is `confirmed`.
    ///   - minContextSlot: The minimum evaluation slot. The default is `nil`.
    ///   - verifiesSignatures: Whether to verify signatures. The default is `false`.
    ///   - replacesRecentBlockhash: Whether to replace the blockhash. The default is `false`.
    public init(
        transaction: Data,
        commitment: Commitment = .confirmed,
        minContextSlot: UInt64? = nil,
        verifiesSignatures: Bool = false,
        replacesRecentBlockhash: Bool = false
    ) {
        self.transaction = transaction
        self.commitment = commitment
        self.minContextSlot = minContextSlot
        self.verifiesSignatures = verifiesSignatures
        self.replacesRecentBlockhash = replacesRecentBlockhash
    }

    /// Encodes the base64 transaction and simulation configuration as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(transaction.base64EncodedString())
        try parameters.encode(Configuration(
            commitment: commitment,
            minContextSlot: minContextSlot,
            sigVerify: verifiesSignatures,
            replaceRecentBlockhash: replacesRecentBlockhash
        ))
    }

    /// The simulation options accompanying the serialized transaction.
    private struct Configuration: Encodable {
        let encoding = "base64"
        let commitment: Commitment
        let minContextSlot: UInt64?
        let sigVerify: Bool
        let replaceRecentBlockhash: Bool
    }
}
