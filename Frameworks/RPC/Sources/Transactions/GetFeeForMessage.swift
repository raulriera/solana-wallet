public import Foundation

/// A request for the network fee of a serialized transaction message.
public struct GetFeeForMessage: RPCRequest {
    public static let method = "getFeeForMessage"

    /// A fee and the ledger context of its calculation.
    public struct Response: Decodable, Sendable {
        public let context: Context

        /// The fee in lamports, or `nil` if the node can't determine it.
        public let value: UInt64?

        /// Creates a fee result.
        ///
        /// - Parameters:
        ///   - context: The ledger context of the fee calculation.
        ///   - value: The fee in lamports, or `nil` if unavailable.
        public init(context: Context, value: UInt64?) {
            self.context = context
            self.value = value
        }

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

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request for the fee of a serialized transaction message at finalized commitment.
    ///
    /// - Parameters:
    ///   - message: The serialized message bytes, without the transaction's signatures.
    ///   - minContextSlot: The minimum evaluation slot, or `nil` for no minimum.
    public init(message: Data, minContextSlot: UInt64? = nil) {
        self.message = message
        self.minContextSlot = minContextSlot
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(message.base64EncodedString())
        try parameters.encode(LedgerConfiguration(minContextSlot: minContextSlot))
    }
}
