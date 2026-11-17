import Foundation
import Testing
@testable import RPC

struct SolanaRPCTests {
    @Test(arguments: [
        (Network.mainnet, "api.mainnet.solana.com"), (.devnet, "api.devnet.solana.com")
    ])
    func `Public Solana endpoints submit signed bytes without a DAS interface`(network: Network, host: String) async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":"accepted-signature""#) }
        let rpc: any RPC = SolanaRPC(network: network, transport: transport)
        let bytes = Data([1, 2, 3])

        let signature = try await rpc.send(SendTransaction(transaction: bytes))

        #expect(signature == "accepted-signature")
        #expect(rpc.network == network)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.host() == host)
        #expect(request.url?.scheme == "https")
        #expect(request.url?.query() == nil)
        let body = try requestBody(request)
        #expect(body["method"] as? String == "sendTransaction")
        let params = try #require(body["params"] as? [Any])
        #expect(params.first as? String == bytes.base64EncodedString())
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        URL(string: "https://rpc.example.com:8443/fixture-token/?api-key=fixture-key")!,
        URL(string: "fixture-token/?api-key=fixture-key", relativeTo: URL(string: "https://rpc.example.com:8443/"))!,
    ])
    func `Custom endpoints receive requests and subscriptions at their URL`(endpoint: URL) async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":12345"#) }
        let socket = SocketFixture()
        defer { socket.cancel() }
        let client = SolanaRPC(endpoint: endpoint, network: .mainnet, transport: transport) { url in
            #expect(url.absoluteString == "wss://rpc.example.com:8443/fixture-token/?api-key=fixture-key")
            return socket
        }
        let rpc = try #require(client)

        _ = try await rpc.send(GetBlockHeight())
        _ = try await rpc.changedSlots(for: ["wallet"])

        #expect(await transport.requests.first?.url?.absoluteString == "https://rpc.example.com:8443/fixture-token/?api-key=fixture-key")
        #expect(socket.subscribedAddresses == ["wallet"])
    }

    @Test(arguments: ["https:///fixture-token", "https://:8443/fixture-token", "https://fixture-user@/fixture-token"])
    func `Custom endpoints require HTTPS and a host`(url: String) throws {
        let endpoint = try #require(URL(string: url))

        #expect(SolanaRPC(endpoint: endpoint, network: .mainnet) == nil)
    }

    @Test
    func `Custom endpoint diagnostics hide the URL and its key`() async throws {
        let endpoint = URL(string: "https://fixture-user:fixture-pass@rpc.example.com/path-token?api-key=query-key&bare-key")!
        let transport = StubTransport { request in
            let url = try #require(request.url?.absoluteString)
            return try reply(to: request, payload: #""error":{"code":-32603,"message":"\#(url) fixture-user fixture-pass path-token query-key bare-key"}"#)
        }
        let rpc = try #require(SolanaRPC(endpoint: endpoint, network: .mainnet, transport: transport))

        let message = Array(repeating: "[redacted]", count: 6).joined(separator: " ")
        await #expect(throws: RPCError.server(code: -32603, message: message)) {
            try await rpc.send(GetBlockHeight())
        }
        #expect(String(describing: rpc) == "SolanaRPC(mainnet)")
        #expect(String(reflecting: rpc) == "SolanaRPC(mainnet)")
    }
}
