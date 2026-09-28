import RPC
import Testing

/// A provider double restricted to signing's fee and expiry checks.
actor SigningRPC: RPC {
    nonisolated let network: Network = .devnet
    private var heights: [UInt64]
    private var validities: [Bool]
    private let validitySlot: UInt64
    private let fee: UInt64?
    private(set) var requests: [any RPCRequest] = []

    /// Creates independent ledger observations for one signing attempt.
    ///
    /// - Parameters:
    ///   - heights: The heights returned before and after authentication.
    ///   - validities: Recent-blockhash checks returned before and after authentication.
    ///   - validitySlot: The ledger slot reported by those validity checks.
    ///   - fee: The newly observed total fee, or `nil` if unavailable.
    init(heights: [UInt64] = [500, 500], fee: UInt64? = 10_000, validities: [Bool] = [true, true], validitySlot: UInt64 = 403) {
        self.heights = heights
        self.validities = validities
        self.validitySlot = validitySlot
        self.fee = fee
    }

    /// Records each read and rejects any attempt to refresh or submit a transaction.
    ///
    /// - Parameter request: A fee or block-height request.
    /// - Returns: The next scripted observation.
    /// - Throws: A test failure if a request is unexpected or its script is exhausted.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        requests.append(request)
        switch request {
        case is GetBlockHeight:
            let height = try #require(heights.first)
            heights.removeFirst()
            return try #require(height as? Request.Response)
        case is IsBlockhashValid:
            try #require(!validities.isEmpty, "Unexpected additional blockhash check")
            let valid = validities.removeFirst()
            return try #require(IsBlockhashValid.Response(context: Context(slot: validitySlot), value: valid) as? Request.Response)
        case is GetFeeForMessage:
            return try #require(GetFeeForMessage.Response(context: Context(slot: 403), value: fee) as? Request.Response)
        default:
            Issue.record("Unexpected signing request: \(Request.method)")
            throw RPCError.invalidResponse(.invalidEnvelope)
        }
    }
}
