import Foundation
import Testing
@testable import RPC

struct AccountReadTests {
    @Test
    func `Account reads preserve bytes and missing accounts at a shared slot`() async throws {
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
        try #require(result.value.count == 2)
        #expect(result.value[1] == nil)
        #expect(result.context.slot == 402)
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "getMultipleAccounts")
        let params = try #require(body["params"] as? [Any])
        #expect(params.first as? [String] == ["mint", "missing"])
        let options = try #require(params.last as? [String: Any])
        #expect(options["encoding"] as? String == "base64")
        #expect(options["commitment"] as? String == "finalized")
        #expect(options["minContextSlot"] as? UInt64 == 400)
    }

    @Test
    func `Account reads encode all 100 addresses in one request`() throws {
        let request = try GetMultipleAccounts(addresses: Array(repeating: "address", count: 100))
        let params = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [Any])
        #expect((params.first as? [String])?.count == 100)
    }

    @Test(arguments: [0, 101])
    func `Account reads reject empty and oversized address lists`(_ count: Int) {
        #expect(throws: GetMultipleAccountsError.invalidAddressCount) {
            try GetMultipleAccounts(addresses: Array(repeating: "address", count: count))
        }
    }

    @Test(arguments: [
        #"["AQID","base58"]"#, #"["!","base64"]"#, #"["AQID"]"#, #"null"#
    ])
    func `Account reads reject malformed base64 representations`(_ data: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":402},"value":[{"owner":"token-program","lamports":1,"executable":false,"data":\#(data)}]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetMultipleAccounts(addresses: ["mint"]))
        }
    }

    @Test
    func `Shared account reads return accounts in request order, missing ones as nil, with their slot`() async throws {
        let transport = StubTransport.replying(accounts: [AccountReplies.account(owner: "program", data: [1]), nil])
        let rpc = SolanaRPC.devnet(transport: transport)

        let response = try await rpc.accounts(at: ["first", "second"], minContextSlot: 7)

        #expect(response.value.map { $0?.data } == [Data([1]), nil])
        #expect(response.context.slot == 7)
        #expect(try await transport.requests.map(requestedAddresses) == [["first", "second"]])
    }

    @Test(arguments: [
        ([nil, nil], nil, RPCError.InvalidResponse.mismatchedAccounts),
        ([nil], 8, .staleContext),
    ] as [([String?], UInt64?, RPCError.InvalidResponse)])
    func `Shared account reads reject responses that don't match the request`(
        accounts: [String?], minContextSlot: UInt64?, reason: RPCError.InvalidResponse
    ) async {
        let rpc = SolanaRPC.devnet(transport: .replying(accounts: accounts))

        await #expect(throws: RPCError.invalidResponse(reason)) {
            try await rpc.accounts(at: ["first"], minContextSlot: minContextSlot)
        }
    }
}
