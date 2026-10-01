import Foundation
import Testing
@testable import RPC

/// Tests priority-fee estimates and their outgoing parameters through the HTTP client.
struct PriorityFeeTests {
    /// Verifies recommended transaction estimates, including zero and fractional prices.
    ///
    /// - Parameter amount: The JSON number returned as the estimated compute-unit price.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get priority fee returns the recommended price in micro-lamports per compute unit",
          arguments: ["0", "10082.25"])
    func getPriorityFeeReturnsTheRecommendedPriceInMicroLamportsPerComputeUnit(amount: String) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"priorityFeeEstimate":\#(amount)}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetPriorityFeeEstimate(for: .transaction(Data([0x81, 0xFB, 0xFF, 0x00]))))

        #expect(response.microLamportsPerComputeUnit == Decimal(string: amount))
        #expect(await transport.requests.count == 1)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [[String: Any]])
        #expect(body["method"] as? String == "getPriorityFeeEstimate")
        try #require(parameters.count == 1)
        let input = parameters[0]
        #expect(input["transaction"] as? String == "gfv/AA==")
        #expect(input.count == 2)
        let options = try #require(input["options"] as? [String: Any])
        #expect(options["transactionEncoding"] as? String == "Base64")
        #expect(options["recommended"] as? Bool == true)
        #expect(options.count == 2)
    }

    /// Verifies that account-based estimates use an explicit level instead of the recommendation.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get priority fee estimates account activity at the requested priority level")
    func getPriorityFeeEstimatesAccountActivityAtTheRequestedPriorityLevel() async throws {
        let addresses = ["11111111111111111111111111111111", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"priorityFeeEstimate":12500}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetPriorityFeeEstimate(for: .accounts(addresses), priority: .high))

        #expect(response.microLamportsPerComputeUnit == 12500)
        let request = try #require(await transport.requests.first)
        let parameters = try #require(try requestBody(request)["params"] as? [[String: Any]])
        try #require(parameters.count == 1)
        let input = parameters[0]
        #expect(input["accountKeys"] as? [String] == addresses)
        #expect(input.count == 2)
        let options = try #require(input["options"] as? [String: Any])
        #expect(options["priorityLevel"] as? String == "High")
        #expect(options["recommended"] as? Bool == false)
        #expect(options.count == 2)
    }

    /// Verifies that unusable estimates can't silently become a zero-fee recommendation.
    ///
    /// - Parameter result: A result with an absent, null, negative, or malformed estimate.
    @Test("get priority fee rejects missing negative or malformed estimates", arguments: [
        "{}",
        #"{"priorityFeeEstimate":null}"#,
        #"{"priorityFeeEstimate":-0.01}"#,
        #"{"priorityFeeEstimate":"unavailable"}"#,
    ])
    func getPriorityFeeRejectsMissingNegativeOrMalformedEstimates(result: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":\#(result)"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetPriorityFeeEstimate(for: .accounts(["11111111111111111111111111111111"])))
        }
    }
}
