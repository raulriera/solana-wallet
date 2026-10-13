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

    /// The confirmation level at which the node performs preflight checks.
    public let preflightCommitment: Commitment

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Whether the node should bypass signature verification and preflight simulation.
    public let skipsPreflight: Bool

    /// The node's retry limit, or `nil` to use its retry policy until finalization or expiry.
    ///
    /// This option controls the node's forwarding attempts. The HTTP client always
    /// makes one request and never resubmits automatically.
    public let maxRetries: UInt64?

    /// Creates a request to submit a fully signed V1 transaction.
    ///
    /// Construction and signing belong to the caller. The request encodes the supplied
    /// bytes as base64 without changing the signatures or blockhash. Use the same
    /// commitment when obtaining the transaction's blockhash and running preflight.
    ///
    /// - Parameters:
    ///   - transaction: The complete serialized, signed V1 transaction.
    ///   - preflightCommitment: The preflight confirmation level. The default is `finalized`.
    ///     The node ignores this option when preflight is skipped.
    ///   - minContextSlot: The minimum evaluation slot. The default is `nil`.
    ///   - skipsPreflight: Whether to bypass preflight checks. The default is `false`.
    ///   - maxRetries: The node's retry limit. The default is zero; `nil` delegates to
    ///     the node's retry policy.
    public init(
        transaction: Data,
        preflightCommitment: Commitment = .finalized,
        minContextSlot: UInt64? = nil,
        skipsPreflight: Bool = false,
        maxRetries: UInt64? = 0
    ) {
        self.transaction = transaction
        self.preflightCommitment = preflightCommitment
        self.minContextSlot = minContextSlot
        self.skipsPreflight = skipsPreflight
        self.maxRetries = maxRetries
    }

    /// Encodes the base64 transaction and submission options as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(transaction.base64EncodedString())
        try parameters.encode(Configuration(
            preflightCommitment: preflightCommitment,
            minContextSlot: minContextSlot,
            skipPreflight: skipsPreflight,
            maxRetries: maxRetries
        ))
    }

    /// The submission options accompanying the signed transaction.
    private struct Configuration: Encodable {
        let encoding = "base64"
        let preflightCommitment: Commitment
        let minContextSlot: UInt64?
        let skipPreflight: Bool
        let maxRetries: UInt64?
    }
}
