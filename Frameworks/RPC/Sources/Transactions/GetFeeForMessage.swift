public import Foundation

/// A request for the network fee associated with a serialized transaction message.
public struct GetFeeForMessage: RPCRequest {
    /// The JSON-RPC method name for calculating a message's fee.
    public static let method = "getFeeForMessage"

    /// A nullable fee and the ledger context in which it was evaluated.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the fee calculation.
        public let context: Context

        /// The fee in lamports, or `nil` if the node can't determine it.
        public let value: UInt64?

        /// Creates a fee result with its ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the fee calculation.
        ///   - value: The fee in lamports, or `nil` if unavailable.
        public init(context: Context, value: UInt64?) {
            self.context = context
            self.value = value
        }

        /// Creates a fee result by decoding its context and required nullable value.
        ///
        /// - Parameter decoder: The decoder containing the fee result.
        /// - Throws: A decoding error if a required field is missing or malformed.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            context = try container.decode(Context.self, forKey: .context)
            value = try container.decode(UInt64?.self, forKey: .value)
        }

        /// The field names in a fee result.
        private enum CodingKeys: String, CodingKey {
            case context, value
        }
    }

    /// The serialized message bytes, without the transaction's signatures.
    public let message: Data

    /// The confirmation level requested for the fee calculation.
    public let commitment: Commitment

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request for the fee of a serialized transaction message.
    ///
    /// Message construction belongs to the caller. This request converts the bytes
    /// to base64 for transport; the server validates the message.
    ///
    /// - Parameters:
    ///   - message: The serialized message bytes, without the transaction's signatures.
    ///   - commitment: The confirmation level to query. The default is `finalized`.
    ///   - minContextSlot: The minimum evaluation slot. The default is `nil`.
    public init(message: Data, commitment: Commitment = .finalized, minContextSlot: UInt64? = nil) {
        self.message = message
        self.commitment = commitment
        self.minContextSlot = minContextSlot
    }

    /// Encodes the base64 message and ledger configuration as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(message.base64EncodedString())
        try parameters.encode(LedgerConfiguration(commitment: commitment, minContextSlot: minContextSlot))
    }
}
