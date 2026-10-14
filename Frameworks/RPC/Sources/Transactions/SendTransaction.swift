public import Foundation

/// A request to submit a fully signed transaction for processing by the cluster.
///
/// A returned signature means the node accepted the transaction, not that execution
/// succeeded. Use ``GetSignatureStatuses`` to check its execution and confirmation.
public struct SendTransaction: RPCRequest {
    /// The JSON-RPC method name for submitting a signed transaction.
    public static let method = "sendTransaction"

    /// The transaction's first signature, encoded as base-58 text.
    public typealias Response = String

    /// The complete serialized, signed V1 transaction supplied by the caller.
    public let transaction: Data

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request to submit a fully signed V1 transaction.
    ///
    /// Construction and signing belong to the caller. The request encodes the supplied
    /// bytes as base64 without changing the signatures or blockhash. Preflight always runs,
    /// at finalized commitment, the same level ``GetLatestBlockhash`` reads. The node doesn't
    /// retry forwarding, and the HTTP client makes one request and never resubmits.
    ///
    /// - Parameters:
    ///   - transaction: The complete serialized, signed V1 transaction.
    ///   - minContextSlot: The minimum evaluation slot. The default is `nil`.
    public init(transaction: Data, minContextSlot: UInt64? = nil) {
        self.transaction = transaction
        self.minContextSlot = minContextSlot
    }

    /// Encodes the base64 transaction and submission options as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(transaction.base64EncodedString())
        try parameters.encode(Configuration(minContextSlot: minContextSlot))
    }

    /// The submission options accompanying the signed transaction.
    private struct Configuration: Encodable {
        let encoding = "base64"
        let preflightCommitment = Commitment.finalized
        let minContextSlot: UInt64?
        let skipPreflight = false
        let maxRetries: UInt64 = 0
    }
}
