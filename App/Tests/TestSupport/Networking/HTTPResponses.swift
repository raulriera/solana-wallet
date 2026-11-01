import Foundation
import Testing
import Transactions
@testable import RPC
@testable import widgets

actor HTTPResponses: HTTPTransport {
    typealias Responder = @Sendable (URLRequest) throws -> String

    private var responses: [String: [String]]
    private let respond: Responder?
    private let prover: StubProver?
    private let error: RPCError?
    private let failingMethod: String?
    private let gate: Suspension?
    private let heldMethod: String?
    private(set) var requests: [URLRequest] = []
    private(set) var wasCancelled = false

    nonisolated var client: HeliusRPC {
        client(socket: { _ in SocketFixture() })
    }

    init(_ responses: [String: [String]], error: RPCError? = nil, failingMethod: String? = nil,
         gate: Suspension? = nil, heldMethod: String? = nil, prover: StubProver? = nil, respond: Responder? = nil) {
        self.responses = responses
        self.respond = respond
        self.prover = prover
        self.error = error
        self.failingMethod = failingMethod
        self.gate = gate
        self.heldMethod = heldMethod
    }

    nonisolated func client(socket: @escaping @Sendable (URL) -> any WebSocketConnection) -> HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: self, socket: socket,
                  zolana: StubProver.zolana(transport: self))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let rpcMethod = body?["method"] as? String
        let method = try rpcMethod ?? #require(request.url?.path())
        if let gate, heldMethod == nil || heldMethod == method { await gate.suspend() }
        wasCancelled = Task.isCancelled
        try Task.checkCancellation()
        if let reply = try prover?.respond(to: request) { return reply }
        let error = failingMethod == nil || failingMethod == method ? self.error : nil
        if case .transport(let code) = error { throw URLError(code) }
        let status: Int
        let headers: [String: String]
        if case .http(let code, let retryAfter) = error {
            status = code
            headers = retryAfter.map { ["Retry-After": $0] } ?? [:]
        } else {
            status = 200
            headers = [:]
        }
        let url = try #require(request.url)
        guard rpcMethod != nil else {
            let respond = try #require(respond, "Unexpected HTTP request: \(method)")
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
            return (Data(try respond(request).utf8), response)
        }
        let value: String
        if status != 200 {
            value = "null"
        } else if let fixture = responses[method]?.first {
            value = fixture
        } else {
            let respond = try #require(respond, "Unexpected HTTP request: \(method)")
            value = try respond(request)
        }
        if (responses[method]?.count ?? 0) > 1 { responses[method]?.removeFirst() }
        let id = try #require(body?["id"] as? String)
        let data = Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(value)}"#.utf8)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status,
                                                    httpVersion: nil, headerFields: headers))
        return (data, response)
    }

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

    static func signing(heights: [UInt64] = [500, 500], fee: UInt64? = 10_000,
                        validities: [Bool] = [true, true], validitySlot: UInt64 = 403) throws -> HTTPResponses {
        HTTPResponses([
            "getBlockHeight": heights.map(String.init),
            "isBlockhashValid": try validities.map { try json(["context": ["slot": validitySlot], "value": $0]) },
            "getFeeForMessage": [try json(["context": ["slot": 403], "value": fee as Any? ?? NSNull()])],
        ])
    }

    static func sending(gate: Suspension? = nil) -> HTTPResponses {
        HTTPResponses([:], gate: gate) { request in
            let encoded = try #require(try request.rpcParameters.first as? String)
            let transaction = try TransactionDecoder().decode(try #require(Data(base64Encoded: encoded)))
            return try json(try #require(transaction.signature))
        }
    }

    static func confirmation(statuses: [GetSignatureStatuses.Response], epochs: [GetEpochInfo.Response] = [],
                             error: RPCError? = nil, failingMethod: String? = nil, gate: Suspension? = nil,
                             heldMethod: String? = nil) throws -> HTTPResponses {
        let values = try statuses.map { response in
            try json(["context": ["slot": response.context.slot], "value": response.value.map { status -> Any in
                guard let status else { return NSNull() }
                return ["slot": status.slot, "confirmations": status.confirmations as Any? ?? NSNull(),
                        "err": errorValue(status.error), "confirmationStatus": status.confirmationStatus?.rawValue as Any? ?? NSNull()]
            }])
        }
        var responses = ["getSignatureStatuses": values]
        if !epochs.isEmpty {
            responses["getEpochInfo"] = try epochs.map {
                try json(["epoch": $0.epoch, "absoluteSlot": $0.absoluteSlot, "blockHeight": $0.blockHeight])
            }
        }
        return HTTPResponses(responses, error: error, failingMethod: failingMethod, gate: gate, heldMethod: heldMethod)
    }

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

    private static func tokenBalance(_ balance: SimulateTransaction.TokenBalance) -> [String: Any] {
        ["accountIndex": balance.accountIndex, "mint": balance.mint,
         "owner": balance.owner as Any? ?? NSNull(), "programId": NSNull(),
         "uiTokenAmount": ["amount": String(balance.amount), "decimals": balance.decimals,
                           "uiAmount": NSNull(), "uiAmountString": String(balance.amount)] as [String: Any]]
    }

    static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
    }

    private static func errorValue(_ error: TransactionError?) -> Any {
        guard let error else { return NSNull() }
        return error.details.map { [error.name: detailValue($0)] } as Any? ?? error.name
    }

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
    func jsonBody() throws -> [String: Any] {
        let data = try #require(httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    var rpcMethod: String { get throws { try #require(jsonBody()["method"] as? String) } }

    var rpcParameters: [Any] { get throws { try #require(jsonBody()["params"] as? [Any]) } }
}
