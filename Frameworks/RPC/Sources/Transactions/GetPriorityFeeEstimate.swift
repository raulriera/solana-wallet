public import Foundation

/// A request for a compute-unit price based on recent transaction activity.
public struct GetPriorityFeeEstimate: RPCRequest {
    /// The JSON-RPC method name for estimating priority fees.
    public static let method = "getPriorityFeeEstimate"

    /// The transaction or accounts whose fee activity should inform the estimate.
    public enum Input: Sendable {
        /// The complete serialized V1 transaction, encoded as base64 by the request.
        case transaction(Data)

        /// The base-58 encoded addresses involved in the intended transaction.
        case accounts([String])
    }

    /// The recommendation or observed fee percentile to request.
    public enum Priority: Sendable {
        /// Uses the provider's recommendation for current network conditions.
        case recommended
        /// Uses the lowest observed fee.
        case minimum
        /// Uses the 25th percentile of observed fees.
        case low
        /// Uses the median observed fee.
        case medium
        /// Uses the 75th percentile of observed fees.
        case high
        /// Uses the 95th percentile of observed fees.
        case veryHigh
        /// Uses the highest observed fee, which may be unnecessarily expensive.
        case unsafeMaximum

        /// The provider's percentile label, or `nil` to request its recommendation.
        fileprivate var level: String? {
            switch self {
            case .recommended: nil
            case .minimum: "Min"
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            case .veryHigh: "VeryHigh"
            case .unsafeMaximum: "UnsafeMax"
            }
        }
    }

    /// An estimated compute-unit price, retaining any fractional micro-lamports.
    public struct Response: Decodable, Sendable {
        /// The suggested price per compute unit in micro-lamports, not the total transaction fee.
        ///
        /// Zero is a valid estimate. Rounding, fee caps, and applying the estimate to
        /// a transaction belong to the caller.
        public let microLamportsPerComputeUnit: Decimal

        /// Creates a priority-fee estimate with an explicit unit.
        ///
        /// - Parameter microLamportsPerComputeUnit: The estimated price per compute unit.
        public init(microLamportsPerComputeUnit: Decimal) {
            self.microLamportsPerComputeUnit = microLamportsPerComputeUnit
        }

        /// Decodes a required, nonnegative compute-unit price.
        ///
        /// - Parameter decoder: The decoder containing the fee estimate.
        /// - Throws: A decoding error if the estimate is missing, null, malformed, or negative.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let estimate = try container.decode(Decimal.self, forKey: .microLamportsPerComputeUnit)
            guard estimate >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .microLamportsPerComputeUnit, in: container,
                    debugDescription: "Expected a nonnegative compute-unit price."
                )
            }
            microLamportsPerComputeUnit = estimate
        }

        /// The field name supplied by the priority-fee API.
        private enum CodingKeys: String, CodingKey {
            case microLamportsPerComputeUnit = "priorityFeeEstimate"
        }
    }

    /// The transaction or account addresses used to select relevant fee activity.
    public let input: Input

    /// The recommendation or fee percentile to request.
    public let priority: Priority

    /// Creates a request for a priority-fee estimate using exactly one input source.
    ///
    /// This request retrieves one estimate without applying it, retrying, or substituting
    /// a fallback fee. The server validates the supplied transaction or addresses.
    ///
    /// - Parameters:
    ///   - input: The serialized transaction or account addresses to analyze.
    ///   - priority: The desired recommendation or percentile. The default is `recommended`.
    public init(for input: Input, priority: Priority = .recommended) {
        self.input = input
        self.priority = priority
    }

    /// Encodes one input source and its fee-selection options as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        var request = parameters.nestedContainer(keyedBy: ParameterKeys.self)
        var options = request.nestedContainer(keyedBy: OptionKeys.self, forKey: .options)
        switch input {
        case .transaction(let data):
            try request.encode(data.base64EncodedString(), forKey: .transaction)
            try options.encode("Base64", forKey: .transactionEncoding)
        case .accounts(let addresses):
            try request.encode(addresses, forKey: .accountKeys)
        }
        let level = priority.level
        try options.encode(level == nil, forKey: .recommended)
        try options.encodeIfPresent(level, forKey: .priorityLevel)
    }

    /// The input and configuration field names accepted by the API.
    private enum ParameterKeys: String, CodingKey {
        case transaction, accountKeys, options
    }

    /// The options used to select one estimate and encode its transaction input.
    private enum OptionKeys: String, CodingKey {
        case transactionEncoding, recommended, priorityLevel
    }
}
