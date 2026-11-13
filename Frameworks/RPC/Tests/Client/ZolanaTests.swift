import CryptoKit
import Foundation
import Testing
@testable import RPC

struct ZolanaTests {
    @Test
    func `Requests keep an endpoint's path and query`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: IndexerFixtures.page()) }
        let endpoint = try #require(URL(string: "https://rings.example.com/base?token=fixture"))
        let zolana = Zolana(network: .devnet, endpoint: endpoint, redactor: SecretRedactor(urls: [endpoint]),
                            transport: transport)

        _ = try await zolana.shieldedTransactions(spending: [IndexerFixtures.bytes(1)])

        #expect(await transport.requests.map { $0.url?.absoluteString } == [
            "https://rings.example.com/base/getShieldedTransactionsByNullifiers?token=fixture",
        ])
    }

    @Test(arguments: Network.allCases)
    func `Attestations pass under each network's policy`(network: Network) async throws {
        let (key, _, recorded) = try AttestedProverKeyTests.attestedKey(on: network)

        #expect(Array(try await key.key().rawRepresentation) == (try recorded.hpkePublicKey))
    }
}
