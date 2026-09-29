import Foundation
import Testing
@testable import RPC

/// Verifies the bounded wire contracts used for account discovery.
struct DiscoveryReadTests {
    /// Verifies each program uses the same ownership lookup and omits unnecessary token data.
    /// - Parameter program: A supported token program's public address.
    @Test("token ownership reads preserve identities and context without downloading token data", arguments: [
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
    ])
    func tokenOwnershipRetainsIdentities(_ program: String) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":402},"value":[{"pubkey":"token-account","account":{"owner":"\#(program)","lamports":2039280,"executable":false,"data":["","base64"]}}]}"#)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let result = try await rpc.send(GetTokenAccountsByOwner(owner: "authority", program: program, minContextSlot: 400))
        let entry = try #require(result.value.first)
        #expect(entry.address == "token-account")
        #expect(entry.account.owner == program)
        #expect(entry.account.data.isEmpty)
        #expect(result.context.slot == 402)
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "getTokenAccountsByOwner")
        let params = try #require(body["params"] as? [Any])
        #expect(params[0] as? String == "authority")
        #expect(params[1] as? [String: String] == ["programId": program])
        let options = try #require(params[2] as? [String: Any])
        #expect(options["dataSlice"] as? [String: Int] == ["offset": 0, "length": 0])
        #expect(options["encoding"] as? String == "base64")
        #expect(options["commitment"] as? String == "confirmed")
        #expect(options["minContextSlot"] as? Int == 400)
    }

    /// Verifies failed execution still represents address activity and only one signature is requested.
    @Test("address history preserves failed transaction evidence and requests only one signature")
    func addressHistoryRetainsFailedExecution() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":[{"signature":"signature","slot":300,"err":"AccountNotFound","memo":null,"blockTime":null,"confirmationStatus":"finalized"}]"#)
        }
        let rpc = Solana(network: .devnet, transport: transport)
        let result = try await rpc.send(GetSignaturesForAddress(address: "authority", minContextSlot: 400))
        #expect(result.first?.signature == "signature")
        #expect(result.first?.slot == 300)
        #expect(result.first?.error?.name == "AccountNotFound")
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "getSignaturesForAddress")
        let params = try #require(body["params"] as? [Any])
        #expect(params[0] as? String == "authority")
        let options = try #require(params[1] as? [String: Any])
        #expect(options["limit"] as? Int == 1)
        #expect(options["minContextSlot"] as? Int == 400)
        #expect(options["commitment"] as? String == "confirmed")
    }
}
