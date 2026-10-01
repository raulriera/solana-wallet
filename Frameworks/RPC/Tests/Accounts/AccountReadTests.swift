import Foundation
import Testing
@testable import RPC

/// Verifies the wire contracts needed to inspect token-transfer prerequisites.
struct AccountReadTests {
    /// Verifies ordered raw bytes, missing accounts, exact lamports, and ledger constraints.
    @Test("account reads preserve bytes and missing accounts at a shared slot")
    func accountReadsPreserveBytesAndMissingAccounts() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":402},"value":[{"owner":"token-program","lamports":18446744073709551615,"executable":false,"data":["AQID","base64"]},null]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let result = try await rpc.send(GetMultipleAccounts(addresses: ["mint", "missing"], minContextSlot: 400))
        let account = try #require(result.value.first ?? nil)
        #expect(account.data == Data([1, 2, 3]))
        #expect(account.lamports == UInt64.max)
        #expect(account.owner == "token-program")
        #expect(!account.executable)
        #expect(result.value.count == 2)
        #expect(result.value[1] == nil)
        #expect(result.context.slot == 402)
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "getMultipleAccounts")
        let params = try #require(body["params"] as? [Any])
        #expect(params.first as? [String] == ["mint", "missing"])
        let options = try #require(params.last as? [String: Any])
        #expect(options["encoding"] as? String == "base64")
        #expect(options["commitment"] as? String == "confirmed")
        #expect(options["minContextSlot"] as? UInt64 == 400)
    }

    /// Verifies one request accepts the provider's limit without silently splitting contexts.
    @Test("account reads encode all 100 addresses in one request")
    func accountReadsEncodeOneHundredAddresses() throws {
        let request = try GetMultipleAccounts(addresses: Array(repeating: "address", count: 100))
        let params = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [Any])
        #expect((params.first as? [String])?.count == 100)
    }

    /// Verifies empty and oversized lists fail before transport can run.
    ///
    /// - Parameter count: An address count outside the supported range.
    @Test("account reads reject empty and oversized address lists", arguments: [0, 101])
    func accountReadsRejectInvalidCounts(_ count: Int) {
        #expect(throws: GetMultipleAccounts.Failure.invalidAddressCount) {
            try GetMultipleAccounts(addresses: Array(repeating: "address", count: count))
        }
    }

    /// Verifies unexpected account representations aren't mistaken for valid raw bytes.
    ///
    /// - Parameter data: An invalid encoding tag, payload, or array shape.
    @Test("account reads reject malformed base64 representations", arguments: [
        #"["AQID","base58"]"#, #"["!","base64"]"#, #"["AQID"]"#, #"null"#
    ])
    func accountReadsRejectMalformedEncoding(_ data: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":402},"value":[{"owner":"token-program","lamports":1,"executable":false,"data":\#(data)}]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetMultipleAccounts(addresses: ["mint"]))
        }
    }

    /// Verifies fee selection receives the exact epoch and its observation slot.
    @Test("epoch reads return the fee schedule epoch and observation slot")
    func epochReadsRetainEpochAndSlot() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"epoch":100,"absoluteSlot":43200001}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let result = try await rpc.send(GetEpochInfo(minContextSlot: 43200000))
        #expect(result.epoch == 100)
        #expect(result.absoluteSlot == 43200001)
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "getEpochInfo")
        let params = try #require(body["params"] as? [[String: Any]])
        #expect(params.first?["commitment"] as? String == "confirmed")
        #expect(params.first?["minContextSlot"] as? UInt64 == 43200000)
    }
}
