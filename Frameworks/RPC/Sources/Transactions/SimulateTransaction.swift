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

        /// The lamports of each transaction account before execution, in account order, or `nil` if unavailable.
        public let preBalances: [UInt64]?

        /// The lamports of each transaction account after execution, in account order, or `nil` if unavailable.
        public let postBalances: [UInt64]?

        /// The token account balances before execution, or `nil` if unavailable.
        public let preTokenBalances: [TokenBalance]?

        /// The token account balances after execution, or `nil` if unavailable.
        public let postTokenBalances: [TokenBalance]?

        /// Creates an execution outcome with its available diagnostics.
        ///
        /// - Parameters:
        ///   - error: The transaction failure, or `nil` if execution succeeded.
        ///   - logs: The program logs, or `nil` if unavailable.
        ///   - unitsConsumed: The consumed compute units, or `nil` if unavailable.
        ///   - loadedAccountsDataSize: The loaded account-data bytes, or `nil` if unavailable.
        ///   - fee: The simulated fee in lamports, or `nil` if unavailable.
        ///   - replacementBlockhash: The replacement blockhash, or `nil` if none was supplied.
        ///   - preBalances: The lamports before execution, or `nil` if unavailable.
        ///   - postBalances: The lamports after execution, or `nil` if unavailable.
        ///   - preTokenBalances: The token balances before execution, or `nil` if unavailable.
        ///   - postTokenBalances: The token balances after execution, or `nil` if unavailable.
        public init(
            error: TransactionError?,
            logs: [String]?,
            unitsConsumed: UInt64?,
            loadedAccountsDataSize: UInt32?,
            fee: UInt64?,
            replacementBlockhash: GetLatestBlockhash.Value?,
            preBalances: [UInt64]?,
            postBalances: [UInt64]?,
            preTokenBalances: [TokenBalance]?,
            postTokenBalances: [TokenBalance]?
        ) {
            self.error = error
            self.logs = logs
            self.unitsConsumed = unitsConsumed
            self.loadedAccountsDataSize = loadedAccountsDataSize
            self.fee = fee
            self.replacementBlockhash = replacementBlockhash
            self.preBalances = preBalances
            self.postBalances = postBalances
            self.preTokenBalances = preTokenBalances
            self.postTokenBalances = postTokenBalances
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
            preBalances = try container.decodeIfPresent([UInt64].self, forKey: .preBalances)
            postBalances = try container.decodeIfPresent([UInt64].self, forKey: .postBalances)
            preTokenBalances = try container.decodeIfPresent([TokenBalance].self, forKey: .preTokenBalances)
            postTokenBalances = try container.decodeIfPresent([TokenBalance].self, forKey: .postTokenBalances)
        }

        /// The field names in the execution result.
        private enum CodingKeys: String, CodingKey {
            case error = "err"
            case logs, unitsConsumed, loadedAccountsDataSize, fee, replacementBlockhash
            case preBalances, postBalances, preTokenBalances, postTokenBalances
        }
    }

    /// A token account's raw balance observed before or after execution.
    public struct TokenBalance: Decodable, Sendable, Equatable {
        /// The token account's index in the transaction's account list.
        public let accountIndex: Int

        /// The mint's Base58 address.
        public let mint: String

        /// The token account's owner, or `nil` if the node didn't record it.
        public let owner: String?

        /// The token program owning the account, or `nil` if the node didn't record it.
        public let program: String?

        /// The balance in raw units, ignoring decimals.
        public let amount: UInt64

        /// The mint's decimal places.
        public let decimals: UInt8

        /// Creates a token balance observation.
        ///
        /// - Parameters:
        ///   - accountIndex: The token account's index in the transaction's account list.
        ///   - mint: The mint's Base58 address.
        ///   - owner: The token account's owner, or `nil` if unrecorded.
        ///   - program: The owning token program, or `nil` if unrecorded.
        ///   - amount: The balance in raw units.
        ///   - decimals: The mint's decimal places.
        public init(accountIndex: Int, mint: String, owner: String?, program: String?, amount: UInt64, decimals: UInt8) {
            self.accountIndex = accountIndex
            self.mint = mint
            self.owner = owner
            self.program = program
            self.amount = amount
            self.decimals = decimals
        }

        /// Decodes the raw amount and decimals from the node's nested token amount.
        ///
        /// - Parameter decoder: The decoder containing the token balance.
        /// - Throws: A decoding error if a required field is missing or the raw amount isn't a whole number of units.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountIndex = try container.decode(Int.self, forKey: .accountIndex)
            mint = try container.decode(String.self, forKey: .mint)
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
            program = try container.decodeIfPresent(String.self, forKey: .programId)
            let tokenAmount = try container.nestedContainer(keyedBy: TokenAmountKeys.self, forKey: .uiTokenAmount)
            let raw = try tokenAmount.decode(String.self, forKey: .amount)
            guard let amount = UInt64(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .amount, in: tokenAmount, debugDescription: "Invalid raw token amount.")
            }
            self.amount = amount
            decimals = try tokenAmount.decode(UInt8.self, forKey: .decimals)
        }

        /// The field names in a token balance.
        private enum CodingKeys: String, CodingKey {
            case accountIndex, mint, owner, programId, uiTokenAmount
        }

        /// The field names in the node's token amount representation.
        private enum TokenAmountKeys: String, CodingKey {
            case amount, decimals
        }
    }

    /// The complete serialized transaction bytes, including its signature slots.
    public let transaction: Data

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Whether the node should verify the transaction's signatures before execution.
    public let verifiesSignatures: Bool

    /// Whether the node should substitute a recent blockhash before execution.
    public let replacesRecentBlockhash: Bool

    /// Creates a simulation request at finalized commitment for a complete serialized transaction.
    ///
    /// The transaction may contain placeholder signatures unless verification is enabled.
    /// Signature verification and blockhash replacement can't both be enabled; the server
    /// validates this combination and the transaction bytes.
    ///
    /// - Parameters:
    ///   - transaction: The complete serialized transaction, including its signature slots.
    ///   - minContextSlot: The minimum evaluation slot. The default is `nil`.
    ///   - verifiesSignatures: Whether to verify signatures. The default is `false`.
    ///   - replacesRecentBlockhash: Whether to replace the blockhash. The default is `false`.
    public init(
        transaction: Data,
        minContextSlot: UInt64? = nil,
        verifiesSignatures: Bool = false,
        replacesRecentBlockhash: Bool = false
    ) {
        self.transaction = transaction
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
            minContextSlot: minContextSlot,
            sigVerify: verifiesSignatures,
            replaceRecentBlockhash: replacesRecentBlockhash
        ))
    }

    /// The simulation options accompanying the serialized transaction.
    private struct Configuration: Encodable {
        let encoding = "base64"
        let commitment = Commitment.finalized
        let minContextSlot: UInt64?
        let sigVerify: Bool
        let replaceRecentBlockhash: Bool
    }
}
