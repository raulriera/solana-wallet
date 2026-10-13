import Foundation
import Testing
@testable import RPC
@testable import widgets

/// HTTP fixtures exercised through the real client's encoding, validation, and decoding.
actor HTTPResponses: HTTPTransport {
    private var responses: [String: [String]]
    private let error: RPCError?
    private let gate: Suspension?
    private let heldMethod: String?
    private(set) var requests: [URLRequest] = []
    private(set) var wasCancelled = false

    /// A real devnet client whose transport never reaches the network.
    nonisolated var client: HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: self)
    }

    /// Creates independent HTTP responses for one test.
    /// - Parameters:
    ///   - responses: JSON result values keyed by RPC method; the last value repeats.
    ///   - error: An optional transport or HTTP failure.
    ///   - gate: An optional suspension for cancellation checks.
    ///   - heldMethod: The method to suspend, or `nil` to suspend every request.
    init(_ responses: [String: [String]], error: RPCError? = nil,
         gate: Suspension? = nil, heldMethod: String? = nil) {
        self.responses = responses
        self.error = error
        self.gate = gate
        self.heldMethod = heldMethod
    }

    /// Records an actual HTTP request and wraps its fixture in a matching JSON-RPC envelope.
    /// - Parameter request: The request encoded by the real client.
    /// - Returns: The response body and HTTP status.
    /// - Throws: A transport, cancellation, or fixture error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let body = try request.jsonBody()
        let method = try #require(body["method"] as? String)
        if let gate, heldMethod == nil || heldMethod == method { await gate.suspend() }
        wasCancelled = Task.isCancelled
        try Task.checkCancellation()
        if case .transport(let code) = error { throw URLError(code) }
        let status: Int
        let headers: [String: String]
        if case .http(let code, let retryAfter) = error {
            status = code
            headers = retryAfter.map { ["Retry-After": $0] } ?? [:]
        } else { status = 200; headers = [:] }
        let value = status == 200 ? try #require(responses[method]?.first, "Unexpected HTTP request: \(method)") : "null"
        if (responses[method]?.count ?? 0) > 1 { responses[method]?.removeFirst() }
        let id = try #require(body["id"] as? String)
        let data = Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(value)}"#.utf8)
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status,
                                                    httpVersion: nil, headerFields: headers))
        return (data, response)
    }

    /// Creates fee, lifetime, and simulation responses from a public transaction fixture.
    ///
    /// An external fixture's confirmed block height is 150 below its expiry bound.
    ///
    /// - Parameters:
    ///   - fixture: The observations to encode as JSON.
    ///   - blockhashError: An optional HTTP failure.
    ///   - blockhashValid: Whether an imported blockhash remains valid.
    ///   - simulationGate: An optional simulation suspension.
    /// - Returns: HTTP responses for the preparation workflow.
    /// - Throws: A JSON encoding or fixture error.
    static func preparation(fixture: Preparation, blockhashError: RPCError? = nil,
                            blockhashValid: Bool = true, simulationGate: Suspension? = nil) throws -> HTTPResponses {
        var responses = [
            "isBlockhashValid": [try json(["context": ["slot": fixture.source.context.slot], "value": blockhashValid])],
            "getFeeForMessage": [try json(["context": ["slot": fixture.fee.context.slot], "value": fixture.fee.value as Any? ?? NSNull()])],
            "simulateTransaction": [try simulation(fixture.simulation)],
        ]
        switch fixture.source {
        case .local(_, _, _, let blockhash):
            responses["getLatestBlockhash"] = [try json(["context": ["slot": blockhash.context.slot],
                "value": ["blockhash": blockhash.value.blockhash, "lastValidBlockHeight": blockhash.value.lastValidBlockHeight]])]
        case .external(_, let lastValidBlockHeight):
            responses["getBlockHeight"] = [String(lastValidBlockHeight - 150)]
        }
        return HTTPResponses(responses, error: blockhashError, gate: simulationGate, heldMethod: "simulateTransaction")
    }

    /// Creates the ledger observations used before and after authentication.
    /// - Parameters:
    ///   - heights: Ordered local block-height observations.
    ///   - fee: The freshly estimated network fee.
    ///   - validities: Ordered imported-blockhash observations.
    ///   - validitySlot: The slot accompanying blockhash checks.
    /// - Returns: HTTP responses for signing validation.
    /// - Throws: A JSON encoding error.
    static func signing(heights: [UInt64] = [500, 500], fee: UInt64? = 10_000,
                        validities: [Bool] = [true, true], validitySlot: UInt64 = 403) throws -> HTTPResponses {
        HTTPResponses([
            "getBlockHeight": heights.map(String.init),
            "isBlockhashValid": try validities.map { try json(["context": ["slot": validitySlot], "value": $0]) },
            "getFeeForMessage": [try json(["context": ["slot": 403], "value": fee as Any? ?? NSNull()])],
        ])
    }

    /// Creates positional signature-status responses through real JSON decoding.
    /// - Parameters:
    ///   - responses: The status observations in arrival order.
    ///   - error: An optional transport or HTTP failure.
    ///   - gate: An optional in-flight suspension.
    /// - Returns: HTTP responses for confirmation.
    /// - Throws: A JSON encoding error.
    static func confirmation(responses: [GetSignatureStatuses.Response], error: RPCError? = nil,
                             gate: Suspension? = nil) throws -> HTTPResponses {
        let values = try responses.map { response in
            try json(["context": ["slot": response.context.slot], "value": response.value.map { status -> Any in
                guard let status else { return NSNull() }
                return ["slot": status.slot, "confirmations": status.confirmations as Any? ?? NSNull(),
                        "err": errorValue(status.error), "confirmationStatus": status.confirmationStatus?.rawValue as Any? ?? NSNull()]
            }])
        }
        return HTTPResponses(["getSignatureStatuses": values], error: error, gate: gate)
    }

    /// Encodes a simulation fixture without adding encoding requirements to production types.
    /// - Parameter response: The public RPC observation.
    /// - Returns: The JSON result value.
    /// - Throws: A JSON encoding error.
    static func simulation(_ response: SimulateTransaction.Response) throws -> String {
        let value = response.value
        return try json(["context": ["slot": response.context.slot], "value": [
            "err": errorValue(value.error), "logs": value.logs as Any? ?? NSNull(),
            "unitsConsumed": value.unitsConsumed as Any? ?? NSNull(),
            "loadedAccountsDataSize": value.loadedAccountsDataSize as Any? ?? NSNull(),
            "fee": value.fee as Any? ?? NSNull(),
            "replacementBlockhash": value.replacementBlockhash.map {
                ["blockhash": $0.blockhash, "lastValidBlockHeight": $0.lastValidBlockHeight] as [String: Any]
            } as Any? ?? NSNull(),
            "preBalances": value.preBalances as Any? ?? NSNull(),
            "postBalances": value.postBalances as Any? ?? NSNull(),
            "preTokenBalances": value.preTokenBalances.map { $0.map(tokenBalance) } as Any? ?? NSNull(),
            "postTokenBalances": value.postTokenBalances.map { $0.map(tokenBalance) } as Any? ?? NSNull(),
        ]])
    }

    /// Encodes a token balance in the node's nested representation.
    /// - Parameter balance: The typed observation.
    /// - Returns: The JSON object, with null attribution fields when unrecorded.
    private static func tokenBalance(_ balance: SimulateTransaction.TokenBalance) -> [String: Any] {
        ["accountIndex": balance.accountIndex, "mint": balance.mint,
         "owner": balance.owner as Any? ?? NSNull(), "programId": balance.program as Any? ?? NSNull(),
         "uiTokenAmount": ["amount": String(balance.amount), "decimals": balance.decimals,
                           "uiAmount": NSNull(), "uiAmountString": String(balance.amount)] as [String: Any]]
    }

    /// Encodes a Foundation JSON value for a fixture envelope.
    /// - Parameter value: An object, array, or scalar supported by JSONSerialization.
    /// - Returns: UTF-8 JSON text.
    /// - Throws: A JSON encoding error.
    static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
    }

    /// Converts an execution error to its JSON-RPC representation.
    /// - Parameter error: The execution error, or `nil` for success.
    /// - Returns: A JSON-compatible value.
    private static func errorValue(_ error: TransactionError?) -> Any {
        guard let error else { return NSNull() }
        return error.details.map { [error.name: detailValue($0)] } as Any? ?? error.name
    }

    /// Converts associated error details without losing integer precision.
    /// - Parameter detail: A nested Solana error detail.
    /// - Returns: A JSON-compatible value.
    private static func detailValue(_ detail: TransactionError.Detail) -> Any {
        switch detail {
        case .string(let value): value
        case .integer(let value): value
        case .array(let values): values.map(detailValue)
        case .object(let values): values.mapValues(detailValue)
        }
    }
}

extension URLRequest {
    /// Decodes the actual request envelope for wire-level assertions.
    /// - Returns: The JSON object sent by the client.
    /// - Throws: A decoding or test prerequisite error.
    func jsonBody() throws -> [String: Any] {
        let data = try #require(httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The JSON-RPC method encoded in the request.
    var rpcMethod: String { get throws { try #require(jsonBody()["method"] as? String) } }

    /// The positional parameters encoded in the request.
    var rpcParameters: [Any] { get throws { try #require(jsonBody()["params"] as? [Any]) } }
}
