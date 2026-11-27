public import Foundation

/// A request to evaluate a serialized transaction without broadcasting it.
public struct SimulateTransaction: RPCRequest {
    public static let method = "simulateTransaction"

    /// An execution outcome and the ledger context of its simulation.
    public struct Response: Decodable, Sendable {
        public let context: Context

        /// The execution outcome.
        public let value: Value

        /// Creates a simulation response.
        ///
        /// - Parameters:
        ///   - context: The ledger context of the simulation.
        ///   - value: The execution outcome.
        public init(context: Context, value: Value) {
            self.context = context
            self.value = value
        }
    }

    /// The outcome of evaluating a transaction, with its diagnostics.
    public struct Value: Decodable, Sendable, Equatable {
        /// The transaction error, or `nil` if execution succeeded.
        public let error: TransactionError?

        /// The program logs, or `nil` if unavailable.
        public let logs: [String]?

        /// The compute units consumed, or `nil` if unavailable.
        public let unitsConsumed: UInt64?

        /// The size in bytes of the account data loaded during execution, or `nil` if unavailable.
        public let loadedAccountsDataSize: UInt32?

        /// The simulated fee in lamports, or `nil` if unavailable.
        public let fee: UInt64?

        /// The replacement blockhash and its expiry height, or `nil` if the node supplied none.
        public let replacementBlockhash: GetLatestBlockhash.Value?

        /// The lamports of each transaction account before execution, in account order, or `nil` if unavailable.
        public let preBalances: [UInt64]?

        /// The lamports of each transaction account after execution, in account order, or `nil` if unavailable.
        public let postBalances: [UInt64]?

        /// The token account balances before execution, or `nil` if unavailable.
        public let preTokenBalances: [TokenBalance]?

        /// The token account balances after execution, or `nil` if unavailable.
        public let postTokenBalances: [TokenBalance]?

        /// Creates an execution outcome.
        ///
        /// - Parameters:
        ///   - error: The transaction error, or `nil` if execution succeeded.
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

    /// A token account's raw balance before or after execution.
    public struct TokenBalance: Decodable, Sendable, Equatable {
        /// The token account's index in the transaction's account list.
        public let accountIndex: Int

        /// The mint's base-58 address.
        public let mint: String

        /// The token account's owner, or `nil` if the node didn't record it.
        public let owner: String?

        /// The balance in raw units, without decimals.
        public let amount: UInt64

        public let decimals: UInt8

        /// Creates a token balance.
        ///
        /// - Parameters:
        ///   - accountIndex: The token account's index in the transaction's account list.
        ///   - mint: The mint's base-58 address.
        ///   - owner: The token account's owner, or `nil` if unrecorded.
        ///   - amount: The balance in raw units.
        ///   - decimals: The mint's decimal places.
        public init(accountIndex: Int, mint: String, owner: String?, amount: UInt64, decimals: UInt8) {
            self.accountIndex = accountIndex
            self.mint = mint
            self.owner = owner
            self.amount = amount
            self.decimals = decimals
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountIndex = try container.decode(Int.self, forKey: .accountIndex)
            mint = try container.decode(String.self, forKey: .mint)
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
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
            case accountIndex, mint, owner, uiTokenAmount
        }

        /// The field names in the node's token amount representation.
        private enum TokenAmountKeys: String, CodingKey {
            case amount, decimals
        }
    }

    /// The serialized transaction bytes, including its signature slots.
    public let transaction: Data

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a simulation request at finalized commitment for a serialized transaction.
    ///
    /// - Parameters:
    ///   - transaction: The serialized transaction, including its signature slots.
    ///   - minContextSlot: The minimum evaluation slot, or `nil` for no minimum.
    public init(transaction: Data, minContextSlot: UInt64? = nil) {
        self.transaction = transaction
        self.minContextSlot = minContextSlot
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(transaction.base64EncodedString())
        try parameters.encode(Configuration(minContextSlot: minContextSlot))
    }

    /// Checks that the simulation comes from the minimum slot or later and kept the transaction's blockhash.
    ///
    /// - Parameter response: The decoded response.
    /// - Throws: ``RPCError/InvalidResponse/staleContext`` if the simulation comes from an earlier slot, or
    ///   ``RPCError/InvalidResponse/replacedBlockhash`` if it replaced the blockhash.
    public func validate(_ response: Response) throws {
        try LedgerConfiguration(minContextSlot: minContextSlot).validate(contextSlot: response.context.slot)
        guard response.value.replacementBlockhash == nil else { throw RPCError.invalidResponse(.replacedBlockhash) }
    }

    /// The simulation options for the serialized transaction.
    private struct Configuration: Encodable {
        let encoding = "base64"
        let commitment = Commitment.finalized
        let minContextSlot: UInt64?
        let sigVerify = false
        let replaceRecentBlockhash = false
    }
}
