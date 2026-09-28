import RPC
import Testing

/// An isolated status script that rejects requests other than signature lookups.
actor ConfirmationRPC: RPC {
    nonisolated let network: Network = .devnet
    private var responses: [GetSignatureStatuses.Response]
    private let failure: RPCError?
    private let gate: Suspension?
    private(set) var requests: [GetSignatureStatuses] = []
    private(set) var wasCancelled = false

    /// Creates status observations without a wallet or a live network connection.
    ///
    /// - Parameters:
    ///   - responses: The ordered observations returned by successive status lookups.
    ///   - failure: An optional RPC error returned on the first lookup.
    ///   - gate: An optional cancellation gate before returning the response.
    init(responses: [GetSignatureStatuses.Response], failure: RPCError? = nil, gate: Suspension? = nil) {
        self.responses = responses
        self.failure = failure
        self.gate = gate
    }

    /// Records a status lookup and returns the next response, even after cancellation.
    ///
    /// - Parameter request: The signature lookup to record.
    /// - Returns: The next scripted status response.
    /// - Throws: The scripted RPC error or a test failure for an unexpected request.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        requests.append(try #require(request as? GetSignatureStatuses))
        if let gate { await gate.suspend() }
        wasCancelled = Task.isCancelled
        if let failure { throw failure }
        try #require(!responses.isEmpty)
        return try #require(responses.removeFirst() as? Request.Response)
    }
}
