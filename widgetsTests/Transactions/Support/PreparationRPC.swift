import RPC
import Testing
@testable import widgets

/// An isolated provider double that only accepts preparation's fee, simulation, and lifetime requests.
actor PreparationRPC: RPC {
    nonisolated let network: Network
    private let fixture: Preparation
    private let blockhashFailure: RPCError?
    private let blockhashValid: Bool
    private let simulationGate: Suspension?
    private(set) var requests: [any RPCRequest] = []
    private(set) var simulationWasCancelled = false

    /// Creates an independent provider for a single test.
    ///
    /// - Parameters:
    ///   - fixture: The typed observations to return.
    ///   - blockhashFailure: An optional failure of the initial request.
    ///   - blockhashValid: Whether the externally supplied recent blockhash remains valid.
    ///   - simulationGate: An optional gate that holds simulation until cancellation.
    init(fixture: Preparation, blockhashFailure: RPCError? = nil, blockhashValid: Bool = true, simulationGate: Suspension? = nil) {
        network = fixture.network
        self.fixture = fixture
        self.blockhashFailure = blockhashFailure
        self.blockhashValid = blockhashValid
        self.simulationGate = simulationGate
    }

    /// Records a typed request and returns its scripted observation.
    ///
    /// - Parameter request: One of the supported preparation requests.
    /// - Returns: The response with the request's exact associated type.
    /// - Throws: The scripted RPC failure, cancellation, or an unexpected-request test failure.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        requests.append(request)
        switch request {
        case is GetLatestBlockhash:
            if let blockhashFailure { throw blockhashFailure }
            let source = try PreparationFixture.source(fixture)
            return try #require(source.blockhash as? Request.Response)
        case is IsBlockhashValid:
            if let blockhashFailure { throw blockhashFailure }
            return try #require(IsBlockhashValid.Response(context: fixture.source.context, value: blockhashValid) as? Request.Response)
        case is GetFeeForMessage:
            return try #require(fixture.fee as? Request.Response)
        case is SimulateTransaction:
            if let simulationGate {
                await simulationGate.suspend()
                simulationWasCancelled = Task.isCancelled
                try Task.checkCancellation()
            }
            return try #require(fixture.simulation as? Request.Response)
        default:
            Issue.record("Unexpected preparation request: \(Request.method)")
            throw RPCError.invalidResponse(.invalidEnvelope)
        }
    }
}
