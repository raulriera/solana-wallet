public import Foundation

/// A request to submit a signed transaction.
public struct SendTransaction: RPCRequest {
    public static let method = "sendTransaction"

    public typealias Response = String

    /// The serialized, signed V1 transaction.
    public let transaction: Data

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request to submit a signed transaction.
    ///
    /// - Parameters:
    ///   - transaction: The serialized, signed V1 transaction.
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

    /// The submission options for the signed transaction.
    private struct Configuration: Encodable {
        let encoding = "base64"
        let preflightCommitment = Commitment.finalized
        let minContextSlot: UInt64?
        let skipPreflight = false
        let maxRetries: UInt64 = 0
    }
}
