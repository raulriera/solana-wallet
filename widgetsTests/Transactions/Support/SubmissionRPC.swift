import RPC
import Testing

/// Records submission attempts while delegating prerequisite reads to an isolated provider.
actor SubmissionRPC: RPC {
    nonisolated let network: Network
    private let checks: any RPC
    private let acknowledgment: String
    private let failure: RPCError?
    private let gate: Suspension?
    private(set) var requests: [any RPCRequest] = []

    /// Creates one submission script without wallet or live network access.
    ///
    /// - Parameters:
    ///   - checks: The provider answering fee and lifetime checks.
    ///   - acknowledgment: The transaction identifier returned after dispatch.
    ///   - failure: An optional provider error returned instead of acknowledgment.
    ///   - gate: An optional suspension that returns late after cancellation.
    ///   - network: The network advertised for submission routing.
    init(checks: any RPC, acknowledgment: String, failure: RPCError? = nil, gate: Suspension? = nil,
         network: Network = .devnet) {
        self.network = network
        self.checks = checks
        self.acknowledgment = acknowledgment
        self.failure = failure
        self.gate = gate
    }

    /// Records requests and returns the scripted acknowledgment without automatically retrying.
    ///
    /// - Parameter request: A prerequisite read or the final submission request.
    /// - Returns: A typed response from the prerequisite provider or the acknowledgment script.
    /// - Throws: The scripted error or a prerequisite provider failure.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        requests.append(request)
        guard request is SendTransaction else { return try await checks.send(request) }
        if let gate { await gate.suspend() }
        if let failure { throw failure }
        return try #require(acknowledgment as? Request.Response)
    }
}
