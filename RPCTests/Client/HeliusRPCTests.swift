import Foundation
import Testing
@testable import RPC

/// Tests typed RPC requests and failures through an injected HTTP transport.
struct HeliusRPCTests {
    private let address = "83astBRguLMdt2h5U1Tpdq5tjFoJ6noeGwaY3mDLVcri"

    /// Verifies that requests reach the Helius endpoint for the selected network.
    ///
    /// - Parameters:
    ///   - network: The Solana network selected when creating the client.
    ///   - expectedHost: The Helius host that should receive the request.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("requests use the selected network endpoint", arguments: [
        (Network.mainnet, "mainnet.helius-rpc.com"),
        (.devnet, "devnet.helius-rpc.com"),
    ])
    func requestsUseTheSelectedNetworkEndpoint(network: Network, expectedHost: String) async throws {
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
    /// - Parameters:
    ///   - query: The request using default or explicit ledger configuration.
    ///   - expectedCommitment: The confirmation level expected in the outgoing request.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when it should be omitted.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get latest blockhash returns a blockhash expiry height and slot", arguments: [
        (GetLatestBlockhash(), "confirmed", UInt64?.none),
        (GetLatestBlockhash(commitment: .finalized, minContextSlot: 12340), "finalized", 12340),
    ])
    func getLatestBlockhashReturnsABlockhashExpiryHeightAndSlot(
        query: GetLatestBlockhash, expectedCommitment: String, expectedSlot: UInt64?
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
        #expect(configuration["commitment"] as? String == expectedCommitment)
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration.count == (expectedSlot == nil ? 1 : 2))
    }

    /// Verifies that a blockhash without its required expiry cannot be returned to a caller.
    @Test("get latest blockhash rejects a response without an expiry height")
    func getLatestBlockhashRejectsAResponseWithoutAnExpiryHeight() async {
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
    /// - Parameters:
    ///   - query: The request using default or explicit ledger configuration.
    ///   - expectedCommitment: The confirmation level expected in the outgoing request.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when it should be omitted.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get block height returns the current ledger height", arguments: [
        (GetBlockHeight(), "confirmed", UInt64?.none),
        (GetBlockHeight(commitment: .processed, minContextSlot: 12340), "processed", 12340),
    ])
    func getBlockHeightReturnsTheCurrentLedgerHeight(
        query: GetBlockHeight, expectedCommitment: String, expectedSlot: UInt64?
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":9007199254740993"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let height = try await rpc.send(query)

        #expect(height == 9_007_199_254_740_993)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [[String: Any]])
        #expect(body["method"] as? String == "getBlockHeight")
        #expect(parameters.count == 1)
        let configuration = try #require(parameters.first)
        #expect(configuration["commitment"] as? String == expectedCommitment)
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration.count == (expectedSlot == nil ? 1 : 2))
    }

    /// Verifies the base64 message, ledger configuration, and decoded fee and slot.
    ///
    /// The bytes are an encoding fixture; this test doesn't construct a transaction.
    ///
    /// - Parameters:
    ///   - query: The request using default or explicit ledger configuration.
    ///   - expectedCommitment: The confirmation level expected in the outgoing request.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when it should be omitted.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get fee for message returns fee lamports and slot", arguments: [
        (GetFeeForMessage(message: Data([0x81, 0xFB, 0xFF, 0x00])), "confirmed", UInt64?.none),
        (GetFeeForMessage(message: Data([0x81, 0xFB, 0xFF, 0x00]), commitment: .finalized, minContextSlot: 12340), "finalized", 12340),
    ])
    func getFeeForMessageReturnsFeeLamportsAndSlot(
        query: GetFeeForMessage, expectedCommitment: String, expectedSlot: UInt64?
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":5000}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(query)

        #expect(response.value == 5000)
        #expect(response.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "getFeeForMessage")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == "gfv/AA==")
        let configuration = try #require(parameters.last as? [String: Any])
        #expect(configuration["commitment"] as? String == expectedCommitment)
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration.count == (expectedSlot == nil ? 1 : 2))
    }

    /// Verifies that an unavailable fee remains distinct from a zero-lamport fee.
    ///
    /// - Throws: An RPC error if the fixture response can't be decoded.
    @Test("get fee for message preserves an unavailable fee and its slot")
    func getFeeForMessagePreservesAnUnavailableFeeAndItsSlot() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":null}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetFeeForMessage(message: Data([0x81, 0xFB, 0xFF, 0x00])))

        #expect(response.value == nil)
        #expect(response.context.slot == 12345)
    }

    /// Verifies that an omitted fee field is rejected rather than treated as an unavailable fee.
    @Test("get fee for message rejects a response without a fee field")
    func getFeeForMessageRejectsAResponseWithoutAFeeField() async {
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
    ///   - expectedCommitment: The confirmation level expected in the request.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when omitted.
    ///   - expectedVerification: Whether signature verification should be requested.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("simulation returns logs compute usage fee and slot", arguments: [
        (SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])), "confirmed", UInt64?.none, false),
        (SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]), commitment: .finalized,
                             minContextSlot: 12340, verifiesSignatures: true), "finalized", 12340, true),
    ])
    func simulationReturnsLogsComputeUsageFeeAndSlot(
        query: SimulateTransaction, expectedCommitment: String, expectedSlot: UInt64?, expectedVerification: Bool
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
        #expect(configuration["commitment"] as? String == expectedCommitment)
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
    @Test("simulation preserves transaction failures and available diagnostics", arguments: [
        (#"{"err":{"InstructionError":[0,{"Custom":6001}]},"logs":["Program log: insufficient funds"],"unitsConsumed":120}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(6001)])])),
         ["Program log: insufficient funds"], UInt64?(120)),
        (#"{"err":"BlockhashNotFound","logs":null,"unitsConsumed":null}"#,
         TransactionError(name: "BlockhashNotFound", details: nil), [String]?.none, UInt64?.none),
    ])
    func simulationPreservesTransactionFailuresAndAvailableDiagnostics(
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
    @Test("simulation returns the replacement blockhash and expiry height")
    func simulationReturnsTheReplacementBlockhashAndExpiryHeight() async throws {
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
    @Test("simulation rejects a response without an execution outcome")
    func simulationRejectsAResponseWithoutAnExecutionOutcome() async {
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
    ///   - expectedCommitment: The preflight confirmation level expected in the request.
    ///   - expectedSlot: The minimum evaluation slot, or `nil` when omitted.
    ///   - expectedSkip: Whether preflight checks should be skipped.
    ///   - expectedRetries: The node's retry limit, or `nil` when omitted.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("send transaction returns the accepted signature and preserves signed bytes", arguments: [
        (SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])), "confirmed", UInt64?.none, false, UInt64?(0)),
        (SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]), preflightCommitment: .processed,
                         minContextSlot: 12340, skipsPreflight: true, maxRetries: 2), "processed", 12340, true, 2),
        (SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]), maxRetries: nil), "confirmed", nil, false, nil),
    ])
    func sendTransactionReturnsTheAcceptedSignatureAndPreservesSignedBytes(
        query: SendTransaction, expectedCommitment: String, expectedSlot: UInt64?, expectedSkip: Bool, expectedRetries: UInt64?
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
        #expect(configuration["preflightCommitment"] as? String == expectedCommitment)
        #expect(configuration["minContextSlot"] as? UInt64 == expectedSlot)
        #expect(configuration["skipPreflight"] as? Bool == expectedSkip)
        #expect(configuration["maxRetries"] as? UInt64 == expectedRetries)
        #expect(configuration.count == 3 + (expectedSlot == nil ? 0 : 1) + (expectedRetries == nil ? 0 : 1))
    }

    /// Verifies that preflight rejection retains its execution failure and simulation diagnostics.
    @Test("send transaction preserves preflight errors and simulation logs without resubmitting")
    func sendTransactionPreservesPreflightErrorsAndSimulationLogsWithoutResubmitting() async {
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
                loadedAccountsDataSize: 142, fee: 5000, replacementBlockhash: nil
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
    @Test("send transaction retains server errors without recognized preflight diagnostics", arguments: [
        (-32002, ""),
        (-32002, #","data":null"#),
        (-32002, #","data":{"logs":[]}"#),
        (-32602, #","data":{"err":null,"logs":[]}"#),
    ])
    func sendTransactionRetainsServerErrorsWithoutRecognizedPreflightDiagnostics(code: Int, dataField: String) async {
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
    @Test("get signature statuses returns confirmation levels and processing slots", arguments: [false, true])
    func getSignatureStatusesReturnsConfirmationLevelsAndProcessingSlots(searchesHistory: Bool) async throws {
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
    @Test("get signature statuses preserves missing transaction positions")
    func getSignatureStatusesPreservesMissingTransactionPositions() async throws {
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
    @Test("get signature statuses returns execution failures for confirmed transactions")
    func getSignatureStatusesReturnsExecutionFailuresForConfirmedTransactions() async throws {
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
    @Test("get signature statuses rejects missing execution or confirmation fields", arguments: [
        #"{"slot":12340,"confirmations":4,"confirmationStatus":"confirmed"}"#,
        #"{"slot":12340,"err":null,"confirmationStatus":"confirmed"}"#,
    ])
    func getSignatureStatusesRejectsMissingExecutionOrConfirmationFields(status: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":[\#(status)]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetSignatureStatuses(signatures: ["example-signature"]))
        }
    }

    /// Verifies named DAS parameters and exact balances, metadata, prices, and indexing information.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get assets returns token balances metadata and native SOL")
    func getAssetsReturnsTokenBalancesMetadataAndNativeSOL() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"last_indexed_slot":12345,"page":2,"limit":1000,"items":[{
                    "id":"mint-address","interface":"FungibleToken",
                    "content":{"metadata":{"name":"Example Token","symbol":"EX"},"links":{"image":"https://example.com/token.png"}},
                    "token_info":{"balance":9007199254740993,"decimals":6,
                        "price_info":{"price_per_token":0.1000000000000000001,"total_price":20.25,"currency":"USD"}}
                }],"nativeBalance":{"lamports":1234567890,"price_per_sol":120.5,"total_price":148.765430745}}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address, page: 2))

        let asset = try #require(response.items.first)
        #expect(asset.id == "mint-address")
        #expect(asset.balance == 9_007_199_254_740_993)
        #expect(asset.decimals == 6)
        #expect(asset.name == "Example Token")
        #expect(asset.symbol == "EX")
        #expect(asset.imageURL?.absoluteString == "https://example.com/token.png")
        #expect(asset.price?.perToken == Decimal(string: "0.1000000000000000001"))
        #expect(asset.price?.total == Decimal(string: "20.25"))
        #expect(asset.price?.currency == "USD")
        #expect(response.nativeBalance?.lamports == 1_234_567_890)
        #expect(response.nativeBalance?.pricePerSOL == Decimal(string: "120.5"))
        #expect(response.lastIndexedSlot == 12345)
        #expect(response.page == 2)
        #expect(response.limit == 1000)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [String: Any])
        #expect(body["method"] as? String == "getAssetsByOwner")
        #expect(parameters["ownerAddress"] as? String == address)
        #expect(parameters["page"] as? Int == 2)
        #expect(parameters["limit"] as? Int == 1000)
        #expect(parameters["options"] as? [String: Bool] == ["showFungible": true, "showNativeBalance": true])
    }

    /// Verifies that malformed display fields preserve exact balances and healthy metadata.
    ///
    /// - Parameters:
    ///   - content: The synthetic content containing malformed display metadata.
    ///   - expectedName: The available name, or `nil` when malformed or missing.
    ///   - expectedSymbol: The available symbol, or `nil` when malformed or missing.
    ///   - expectedImageURL: The available image, or `nil` when none can be decoded.
    /// - Throws: An RPC error or a failed test prerequisite.
    @Test("get assets preserves holdings when display metadata is malformed", arguments: [
        (#"{"metadata":{"name":"Example Collectible"},"links":{"image":false},"files":[]}"#,
         "Example Collectible", nil as String?, nil as String?),
        (#"{"metadata":{"name":"Example Collectible"},"links":{"image":false},"files":[{"uri":"https://example.com/fallback.png","mime":"image/png"}]}"#,
         "Example Collectible", nil, "https://example.com/fallback.png"),
        (#"{"metadata":{"name":false,"symbol":"EX"},"links":{"image":"https://example.com/token.png"}}"#,
         nil, "EX", "https://example.com/token.png"),
        (#"{"metadata":{"name":"Example Collectible","symbol":false},"files":[false,{"uri":false,"mime":"image/png"},{"uri":"https://example.com/ignored.png","mime":false},{"uri":"https://example.com/fallback.png","mime":"image/png"}]}"#,
         "Example Collectible", nil, "https://example.com/fallback.png"),
        (#"{"metadata":false,"links":false,"files":false}"#, nil, nil, nil),
        ("false", nil, nil, nil),
    ])
    func getAssetsPreservesHoldingsWhenDisplayMetadataIsMalformed(
        content: String, expectedName: String?, expectedSymbol: String?, expectedImageURL: String?
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"page":1,"limit":1000,"items":[
                    {"id":"collectible","interface":"V1_NFT","content":\#(content),
                     "token_info":{"balance":1,"decimals":0,"symbol":false}},
                    {"id":"mint-address","interface":"FungibleToken",
                     "token_info":{"balance":42,"decimals":6}}
                ],"nativeBalance":{"lamports":12345}}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address))

        #expect(response.items.map(\.id) == ["collectible", "mint-address"])
        let collectible = try #require(response.items.first)
        #expect(collectible.name == expectedName)
        #expect(collectible.symbol == expectedSymbol)
        #expect(collectible.imageURL?.absoluteString == expectedImageURL)
        #expect(collectible.balance == 1)
        #expect(collectible.decimals == 0)
        let token = try #require(response.items.last)
        #expect(token.balance == 42)
        #expect(token.decimals == 6)
        #expect(response.nativeBalance?.lamports == 12345)
    }

    /// Verifies that metadata recovery never accepts malformed asset identity or amounts.
    ///
    /// - Parameter asset: A synthetic asset with an invalid required identity or supplied amount.
    @Test("get assets rejects malformed identity and amount fields", arguments: [
        #"{"id":false,"interface":"FungibleToken"}"#,
        #"{"id":"mint","interface":"FungibleToken","token_info":{"balance":"unknown","decimals":6}}"#,
        #"{"id":"mint","interface":"FungibleToken","token_info":{"balance":42,"decimals":1.5}}"#,
    ])
    func getAssetsRejectsMalformedIdentityAndAmountFields(asset: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"page":1,"limit":1000,"items":[\#(asset)]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetAssetsByOwner(owner: address))
        }
    }

    /// Verifies that a token remains available when metadata and prices are absent.
    ///
    /// - Throws: An RPC error or a failed test prerequisite.
    @Test("get assets preserves balances without metadata or prices")
    func getAssetsPreservesBalancesWithoutMetadataOrPrices() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"page":1,"limit":1000,"items":[{"id":"unknown-mint","interface":"FungibleToken","token_info":{"balance":18446744073709551615,"decimals":9}}]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address))

        let asset = try #require(response.items.first)
        #expect(asset.balance == UInt64.max)
        #expect(asset.name == nil)
        #expect(asset.symbol == nil)
        #expect(asset.imageURL == nil)
        #expect(asset.price == nil)
        #expect(response.lastIndexedSlot == nil)
    }

    /// Verifies that a wallet without assets retains an explicit zero native balance.
    ///
    /// - Throws: An RPC error.
    @Test("get assets returns an empty asset list and zero native SOL")
    func getAssetsReturnsAnEmptyAssetListAndZeroNativeSOL() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"page":1,"limit":1000,"items":[],"nativeBalance":{"lamports":0}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address))

        #expect(response.items.isEmpty)
        #expect(response.nativeBalance?.lamports == 0)
    }

    /// Verifies that an invalid-address rejection preserves the server's code and message.
    @Test("get assets reports an invalid wallet address")
    func getAssetsReportsAnInvalidWalletAddress() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":-32602,"message":"Invalid param: WrongSize"}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.server(code: -32602, message: "Invalid param: WrongSize")) {
            try await rpc.send(GetAssetsByOwner(owner: "invalid-address"))
        }
    }

    /// Verifies that server errors returned by the client omit its API key and endpoint.
    ///
    /// - Parameters:
    ///   - network: The Solana network whose authenticated endpoint to redact.
    ///   - includesSimulation: Whether the rejection contains preflight simulation logs.
    @Test("server errors hide API keys and authenticated URLs", arguments: [Network.mainnet, .devnet], [false, true])
    func serverErrorsHideAPIKeysAndAuthenticatedURLs(network: Network, includesSimulation: Bool) async {
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
                unitsConsumed: nil, loadedAccountsDataSize: nil, fee: nil, replacementBlockhash: nil
            ))
            : .server(code: code, message: message)

        await #expect(throws: expectedError) {
            try await rpc.send(SendTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
    }

    /// Verifies that rate limiting exposes the retry delay without another HTTP attempt.
    @Test("rate limited requests expose the retry delay without retrying")
    func rateLimitedRequestsExposeTheRetryDelayWithoutRetrying() async {
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
    @Test("responses belonging to another request are rejected")
    func responsesBelongingToAnotherRequestAreRejected() async {
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
    @Test("cancelling during encoding prevents the HTTP request", arguments: [false, true])
    func cancellingDuringEncodingPreventsTheHTTPRequest(throwsCancellation: Bool) async {
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
    @Test("cancelling during decoding surfaces a cancellation error", arguments: [false, true])
    func cancellingDuringDecodingSurfacesACancellationError(throwsCancellation: Bool) async {
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
    @Test("cancelling a request cancels the HTTP operation", .timeLimit(.minutes(1)))
    func cancellingARequestCancelsTheHTTPOperation() async throws {
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
