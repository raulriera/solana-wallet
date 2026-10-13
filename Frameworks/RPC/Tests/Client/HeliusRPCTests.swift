import Foundation
import Testing
@testable import RPC

/// Tests typed RPC requests and failures through an injected HTTP transport.
struct HeliusRPCTests {
    /// Verifies that requests reach the Helius endpoint for the selected network.
    ///
    /// - Parameters:
    ///   - network: The Solana network selected when creating the client.
    ///   - expectedHost: The Helius host that should receive the request.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [
        (Network.mainnet, "mainnet.helius-rpc.com"),
        (.devnet, "devnet.helius-rpc.com"),
    ])
    func `Requests use the selected network endpoint`(network: Network, expectedHost: String) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":12345"#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", network: network, transport: transport)

        _ = try await rpc.send(GetBlockHeight())

        let request = try #require(await transport.requests.first)
        #expect(request.url?.host() == expectedHost)
        #expect(rpc.network == network)
        #expect(try requestBody(request)["jsonrpc"] as? String == "2.0")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 30)
        let url = try #require(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "api-key", value: "test-key")])
    }

    /// Verifies the blockhash request, its expiry height, and its independent ledger slot.
    ///
    /// This test also covers the configuration that ledger requests share: finalized
    /// commitment, and no minimum evaluation slot when it's `nil`.
    ///
    /// - Parameters:
    ///   - query: The request with or without a minimum evaluation slot.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when it should be omitted.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [
        (GetLatestBlockhash(), UInt64?.none),
        (GetLatestBlockhash(minContextSlot: 12340), UInt64?(12340)),
    ])
    func `Get latest blockhash returns a blockhash expiry height and slot`(
        query: GetLatestBlockhash, expectedSlot: UInt64?
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":{"blockhash":"EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N","lastValidBlockHeight":9007199254740993}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(query)

        #expect(response.value.blockhash == "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N")
        #expect(response.value.lastValidBlockHeight == 9_007_199_254_740_993)
        #expect(response.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [[String: Any]])
        #expect(body["method"] as? String == "getLatestBlockhash")
        #expect(parameters.count == 1)
        let configuration = try #require(parameters.first)
        #expect(configuration["commitment"] as? String == "finalized")
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration.count == (expectedSlot == nil ? 1 : 2))
    }

    /// Verifies that a blockhash without its required expiry cannot be returned to a caller.
    @Test
    func `Get latest blockhash rejects a response without an expiry height`() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":{"blockhash":"EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N"}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetLatestBlockhash())
        }
    }

    /// Verifies the height request and exact integer decoding without a context envelope.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Get block height returns the current ledger height`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":9007199254740993"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let height = try await rpc.send(GetBlockHeight(minContextSlot: 12340))

        #expect(height == 9_007_199_254_740_993)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [[String: Any]])
        #expect(body["method"] as? String == "getBlockHeight")
        #expect(parameters.count == 1)
        #expect(parameters.first?["minContextSlot"] as? UInt64 == 12340)
    }

    /// Verifies the base64 message, minimum evaluation slot, and decoded fee and slot.
    ///
    /// The bytes are an encoding fixture; this test doesn't construct a transaction.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Get fee for message returns fee lamports and slot`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":5000}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetFeeForMessage(message: Data([0x81, 0xFB, 0xFF, 0x00]), minContextSlot: 12340))

        #expect(response.value == 5000)
        #expect(response.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "getFeeForMessage")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == "gfv/AA==")
        let configuration = try #require(parameters.last as? [String: Any])
        #expect(configuration["minContextSlot"] as? UInt64 == 12340)
    }

    /// Verifies that an unavailable fee remains distinct from a zero-lamport fee.
    ///
    /// - Throws: An RPC error if the fixture response can't be decoded.
    @Test
    func `Get fee for message preserves an unavailable fee and its slot`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":null}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetFeeForMessage(message: Data([0x81, 0xFB, 0xFF, 0x00])))

        #expect(response.value == nil)
        #expect(response.context.slot == 12345)
    }

    /// Verifies that an omitted fee field is rejected rather than treated as an unavailable fee.
    @Test
    func `Get fee for message rejects a response without a fee field`() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetFeeForMessage(message: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
    }

    /// Verifies simulation diagnostics and the base64 transaction's execution options.
    ///
    /// The bytes are a transport fixture, not a constructed transaction.
    ///
    /// - Parameters:
    ///   - query: The request using default or explicit execution options.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when omitted.
    ///   - expectedVerification: Whether signature verification should be requested.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [
        (SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])), UInt64?.none, false),
        (SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]), minContextSlot: 12340, verifiesSignatures: true),
         12340, true),
    ])
    func `Simulation returns logs compute usage fee and slot`(
        query: SimulateTransaction, expectedSlot: UInt64?, expectedVerification: Bool
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":{
                    "err":null,"logs":["Program log: transfer","Program 11111111111111111111111111111111 success"],
                    "unitsConsumed":1714,"loadedAccountsDataSize":413,"fee":5000,"replacementBlockhash":null
                }}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(query)

        #expect(response.context.slot == 12345)
        #expect(response.value.error == nil)
        #expect(response.value.logs == ["Program log: transfer", "Program 11111111111111111111111111111111 success"])
        #expect(response.value.unitsConsumed == 1714)
        #expect(response.value.loadedAccountsDataSize == 413)
        #expect(response.value.fee == 5000)
        #expect(response.value.replacementBlockhash == nil)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "simulateTransaction")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == "gfv/AA==")
        let configuration = try #require(parameters.last as? [String: Any])
        #expect(configuration["encoding"] as? String == "base64")
        #expect(configuration["commitment"] as? String == "finalized")
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration["sigVerify"] as? Bool == expectedVerification)
        #expect(configuration["replaceRecentBlockhash"] as? Bool == false)
        #expect(configuration.count == (expectedSlot == nil ? 4 : 5))
    }

    /// Verifies that execution failures retain available diagnostics without becoming RPC errors.
    ///
    /// - Parameters:
    ///   - value: The simulation outcome encoded by the fixture.
    ///   - expectedError: The expected transaction failure.
    ///   - expectedLogs: The available logs, or `nil` when execution never began.
    ///   - expectedUnits: The consumed compute units, or `nil` if unavailable.
    /// - Throws: An RPC error if the fixture response can't be decoded.
    @Test(arguments: [
        (#"{"err":{"InstructionError":[0,{"Custom":6001}]},"logs":["Program log: insufficient funds"],"unitsConsumed":120}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(6001)])])),
         ["Program log: insufficient funds"], UInt64?(120)),
        (#"{"err":"BlockhashNotFound","logs":null,"unitsConsumed":null}"#,
         TransactionError(name: "BlockhashNotFound", details: nil), [String]?.none, UInt64?.none),
    ])
    func `Simulation preserves transaction failures and available diagnostics`(
        value: String, expectedError: TransactionError, expectedLogs: [String]?, expectedUnits: UInt64?
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":\#(value)}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))

        #expect(response.context.slot == 12345)
        #expect(response.value.error == expectedError)
        #expect(response.value.logs == expectedLogs)
        #expect(response.value.unitsConsumed == expectedUnits)
        #expect(response.value.fee == nil)
        #expect(response.value.loadedAccountsDataSize == nil)
        #expect(response.value.replacementBlockhash == nil)
    }

    /// Verifies blockhash replacement options and the returned replacement's expiry height.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Simulation returns the replacement blockhash and expiry height`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":{"err":null,"replacementBlockhash":{
                    "blockhash":"EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N","lastValidBlockHeight":12000
                }}}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(SimulateTransaction(
            transaction: Data([0x81, 0xFB, 0xFF, 0x00]), replacesRecentBlockhash: true
        ))

        let replacement = try #require(response.value.replacementBlockhash)
        #expect(replacement.blockhash == "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N")
        #expect(replacement.lastValidBlockHeight == 12000)
        let request = try #require(await transport.requests.first)
        let parameters = try #require(try requestBody(request)["params"] as? [Any])
        let configuration = try #require(parameters.last as? [String: Any])
        #expect(configuration["replaceRecentBlockhash"] as? Bool == true)
        #expect(configuration["sigVerify"] as? Bool == false)
    }

    /// Verifies that a missing execution-error field can't be mistaken for success.
    @Test
    func `Simulation rejects a response without an execution outcome`() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":{"logs":[]}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
    }

    /// Verifies unchanged transaction bytes, submission options, and the returned signature.
    ///
    /// - Parameters:
    ///   - query: The request using default or explicit submission options.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when omitted.
    ///   - expectedSkip: Whether preflight checks should be skipped.
    ///   - expectedRetries: The node's retry limit, or `nil` when omitted.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [
        (SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])), UInt64?.none, false, UInt64?(0)),
        (SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]), minContextSlot: 12340, skipsPreflight: true,
                         maxRetries: 2), 12340, true, 2),
        (SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]), maxRetries: nil), nil, false, nil),
    ])
    func `Send transaction returns the accepted signature and preserves signed bytes`(
        query: SendTransaction, expectedSlot: UInt64?, expectedSkip: Bool, expectedRetries: UInt64?
    ) async throws {
        let signature = "2id3YC2jK9G5Wo2phDx4gJVAew8DcY5NAojnVuao8rkxwPYPe8cSwE5GzhEgJA2y8fVjDEo6iR6ykBvDxrTQrtpb"
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":"\#(signature)""#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let result = try await rpc.send(query)

        #expect(result == signature)
        #expect(await transport.requests.count == 1)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "sendTransaction")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == "gfv/AA==")
        let configuration = try #require(parameters.last as? [String: Any])
        #expect(configuration["encoding"] as? String == "base64")
        #expect(configuration["preflightCommitment"] as? String == "finalized")
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration["skipPreflight"] as? Bool == expectedSkip)
        #expect(configuration["maxRetries"] as? UInt64 == expectedRetries)
        #expect(configuration.count == 3 + (expectedSlot == nil ? 0 : 1) + (expectedRetries == nil ? 0 : 1))
    }

    /// Verifies that preflight rejection retains its execution failure and simulation diagnostics.
    @Test
    func `Send transaction preserves preflight errors and simulation logs without resubmitting`() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "error":{"code":-32002,"message":"Transaction simulation failed","data":{
                    "err":{"InstructionError":[0,{"Custom":1}]},
                    "logs":["Transfer: insufficient lamports"],"unitsConsumed":150,
                    "loadedAccountsDataSize":142,"fee":5000,"replacementBlockhash":null
                }}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.preflight(
            message: "Transaction simulation failed",
            simulation: SimulateTransaction.Value(
                error: TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(1)])])),
                logs: ["Transfer: insufficient lamports"], unitsConsumed: 150,
                loadedAccountsDataSize: 142, fee: 5000, replacementBlockhash: nil,
                preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
            )
        )) {
            try await rpc.send(SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
        #expect(await transport.requests.count == 1)
    }

    /// Verifies that absent or unrecognized diagnostic data doesn't hide the server's rejection.
    ///
    /// - Parameters:
    ///   - code: The server's rejection code.
    ///   - dataField: An optional JSON field containing error-specific diagnostics.
    @Test(arguments: [
        (-32002, ""),
        (-32002, #","data":null"#),
        (-32002, #","data":{"logs":[]}"#),
        (-32602, #","data":{"err":null,"logs":[]}"#),
    ])
    func `Send transaction retains server errors without recognized preflight diagnostics`(code: Int, dataField: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":\#(code),"message":"Submission rejected"\#(dataField)}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.server(code: code, message: "Submission rejected")) {
            try await rpc.send(SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
    }

    /// Verifies status order, confirmation levels, and default or explicit history lookup.
    ///
    /// - Parameter searchesHistory: Whether to query beyond the recent status cache.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [false, true])
    func `Get signature statuses returns confirmation levels and processing slots`(searchesHistory: Bool) async throws {
        let signatures = ["processed-signature", "confirmed-signature", "finalized-signature"]
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":[
                    {"slot":12344,"confirmations":0,"err":null,"confirmationStatus":"processed"},
                    {"slot":12330,"confirmations":14,"err":null,"confirmationStatus":"confirmed"},
                    {"slot":12000,"confirmations":null,"err":null,"confirmationStatus":"finalized"}
                ]}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let query = searchesHistory
            ? GetSignatureStatuses(signatures: signatures, searchesTransactionHistory: true)
            : GetSignatureStatuses(signatures: signatures)

        let response = try await rpc.send(query)

        #expect(response.context.slot == 12345)
        try #require(response.value.count == 3)
        let processed = try #require(response.value[0])
        let confirmed = try #require(response.value[1])
        let finalized = try #require(response.value[2])
        #expect(processed.slot == 12344)
        #expect(processed.confirmations == 0)
        #expect(processed.confirmationStatus == .processed)
        #expect(processed.error == nil)
        #expect(confirmed.slot == 12330)
        #expect(confirmed.confirmations == 14)
        #expect(confirmed.confirmationStatus == .confirmed)
        #expect(confirmed.error == nil)
        #expect(finalized.slot == 12000)
        #expect(finalized.confirmations == nil)
        #expect(finalized.confirmationStatus == .finalized)
        #expect(finalized.error == nil)
        #expect(await transport.requests.count == 1)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "getSignatureStatuses")
        #expect(parameters.count == 2)
        #expect(parameters.first as? [String] == signatures)
        #expect(parameters.last as? [String: Bool] == ["searchTransactionHistory": searchesHistory])
    }

    /// Verifies that an unknown signature retains its position beside a known transaction.
    ///
    /// - Throws: An RPC error or a failed test prerequisite.
    @Test
    func `Get signature statuses preserves missing transaction positions`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":[
                    null,{"slot":12344,"confirmations":0,"err":null,"confirmationStatus":null}
                ]}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetSignatureStatuses(signatures: ["unknown-signature", "known-signature"]))

        try #require(response.value.count == 2)
        #expect(response.value[0] == nil)
        let status = try #require(response.value[1])
        #expect(status.slot == 12344)
        #expect(status.confirmationStatus == nil)
    }

    /// Verifies that a confirmed transaction can retain an execution failure as status data.
    ///
    /// - Throws: An RPC error or a failed test prerequisite.
    @Test
    func `Get signature statuses returns execution failures for confirmed transactions`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":[{
                    "slot":12340,"confirmations":4,"err":{"InstructionError":[0,{"Custom":1}]},
                    "confirmationStatus":"confirmed"
                }]}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetSignatureStatuses(signatures: ["failed-signature"]))

        try #require(response.value.count == 1)
        let status = try #require(response.value[0])
        #expect(status.confirmationStatus == .confirmed)
        #expect(status.error == TransactionError(
            name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(1)])])
        ))
    }

    /// Verifies that omitted fields can't be mistaken for successful or finalized execution.
    ///
    /// - Parameter status: A status missing its execution error or confirmation count field.
    @Test(arguments: [
        #"{"slot":12340,"confirmations":4,"confirmationStatus":"confirmed"}"#,
        #"{"slot":12340,"err":null,"confirmationStatus":"confirmed"}"#,
    ])
    func `Get signature statuses rejects missing execution or confirmation fields`(status: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":[\#(status)]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetSignatureStatuses(signatures: ["example-signature"]))
        }
    }

    /// Verifies that server errors returned by the client omit its API key and endpoint.
    ///
    /// - Parameters:
    ///   - network: The Solana network whose authenticated endpoint to redact.
    ///   - includesSimulation: Whether the rejection contains preflight simulation logs.
    @Test(arguments: [Network.mainnet, .devnet], [false, true])
    func `Server errors hide API keys and authenticated URLs`(network: Network, includesSimulation: Bool) async {
        let apiKey = "test-key"
        let code = includesSimulation ? -32002 : -32603
        let transport = StubTransport { request in
            let endpoint = try #require(request.url?.absoluteString)
            let diagnostics = includesSimulation
                ? #","data":{"err":"BlockhashNotFound","logs":["Request \#(endpoint) failed for \#(apiKey)"]}"#
                : ""
            return try reply(to: request,
                             payload: #""error":{"code":\#(code),"message":"Request \#(endpoint) failed for \#(apiKey)"\#(diagnostics)}"#)
        }
        let rpc = HeliusRPC(apiKey: apiKey, network: network, transport: transport)
        let message = "Request [redacted] failed for [redacted]"
        let expectedError: RPCError = includesSimulation
            ? .preflight(message: message, simulation: SimulateTransaction.Value(
                error: TransactionError(name: "BlockhashNotFound", details: nil), logs: [message],
                unitsConsumed: nil, loadedAccountsDataSize: nil, fee: nil, replacementBlockhash: nil,
                preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
            ))
            : .server(code: code, message: message)

        await #expect(throws: expectedError) {
            try await rpc.send(SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
    }

    /// Verifies that rate limiting exposes the retry delay without another HTTP attempt.
    @Test
    func `Rate limited requests expose the retry delay without retrying`() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":-32005,"message":"Too many requests"}"#,
                      status: 429, headers: ["Retry-After": "5"])
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "5")) {
            try await rpc.send(GetBlockHeight())
        }
        #expect(await transport.requests.count == 1)
    }

    /// Verifies that a response with a different request identifier is rejected.
    @Test
    func `Responses belonging to another request are rejected`() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":100"#,
                      id: "another-request")
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await rpc.send(GetBlockHeight())
        }
    }

    /// Verifies cancellation before networking even if the encoder returns normally.
    ///
    /// - Parameter throwsCancellation: Whether the encoder also throws after cancelling its task.
    @Test(arguments: [false, true])
    func `Cancelling during encoding prevents the HTTP request`(throwsCancellation: Bool) async {
        let transport = StubTransport { request in try reply(to: request, payload: #""result":false"#) }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let task = Task { @concurrent in
            try await rpc.send(CodingCancellationRequest(cancelsDuringEncoding: true, throwsCancellation: throwsCancellation))
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies that cancellation during decoding never becomes a result or decoding error.
    ///
    /// - Parameter throwsCancellation: Whether the decoder also throws after cancelling its task.
    @Test(arguments: [false, true])
    func `Cancelling during decoding surfaces a cancellation error`(throwsCancellation: Bool) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":\#(throwsCancellation)"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let task = Task { @concurrent in
            try await rpc.send(CodingCancellationRequest(cancelsDuringEncoding: false, throwsCancellation: throwsCancellation))
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.requests.count == 1)
    }

    /// Verifies transport cancellation after an RPC request has started.
    ///
    /// Streams coordinate request startup and cancellation without timed sleeps.
    ///
    /// - Throws: A test prerequisite error if the transport doesn't signal startup.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling a request cancels the HTTP operation`() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, pendingContinuation) = AsyncStream<Void>.makeStream()
        let transport = StubTransport { _ in
            startedContinuation.yield(())
            for await _ in pending {}
            throw URLError(.cancelled)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let task = Task { @concurrent in try await rpc.send(GetBlockHeight()) }
        defer {
            task.cancel()
            startedContinuation.finish()
            pendingContinuation.finish()
        }
        var iterator = started.makeAsyncIterator()
        try #require(await iterator.next() != nil)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.observedCancellation)
    }
}

/// A request that triggers cancellation inside a synchronous coding operation.
private struct CodingCancellationRequest: RPCRequest {
    static let method = "example"
    let cancelsDuringEncoding: Bool
    let throwsCancellation: Bool

    /// Encodes empty parameters and optionally cancels the encoding task.
    ///
    /// - Parameter encoder: The encoder receiving the request parameters.
    /// - Throws: `CancellationError` when the fixture is configured to throw during encoding.
    func encode(to encoder: any Encoder) throws {
        _ = encoder.unkeyedContainer()
        if cancelsDuringEncoding {
            withUnsafeCurrentTask { $0?.cancel() }
            if throwsCancellation { throw CancellationError() }
        }
    }

    /// A response that deterministically cancels its own decoding task.
    struct Response: Decodable, Sendable {
        /// Decodes whether to throw, then cancels the current task.
        ///
        /// - Parameter decoder: The decoder containing the fixture's throwing behavior.
        /// - Throws: A decoding error, or `CancellationError` when configured to throw.
        init(from decoder: any Decoder) throws {
            let throwsCancellation = try decoder.singleValueContainer().decode(Bool.self)
            withUnsafeCurrentTask { $0?.cancel() }
            if throwsCancellation { throw CancellationError() }
        }
    }
}
