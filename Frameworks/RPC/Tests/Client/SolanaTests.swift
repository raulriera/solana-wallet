import Foundation
import Testing
@testable import RPC

/// Verifies the public endpoint adapter uses the shared typed request transport.
struct SolanaTests {
    /// Verifies public endpoints receive ordinary RPC submission without credentials or DAS.
    ///
    /// - Parameters:
    ///   - network: The selected Solana network.
    ///   - host: The public endpoint expected for that network.
    @Test(arguments: [
        (Network.mainnet, "api.mainnet.solana.com"), (.devnet, "api.devnet.solana.com")
    ])
    func `Public Solana endpoints submit signed bytes without a DAS interface`(network: Network, host: String) async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":"accepted-signature""#) }
        let rpc: any RPC = Solana(network: network, transport: transport)
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
}
