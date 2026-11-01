import Foundation
import Testing
@testable import RPC

struct ZolanaTests {
    @Test(arguments: IndexerFixtures.hosts)
    func `Reads go to the network's indexer host without a query`(network: Network, host: String) async throws {
        let transport = StubTransport { try reply(to: $0, payload: IndexerFixtures.page()) }
        let zolana = Zolana(network: network, transport: transport)

        _ = try await zolana.shieldedTransactions(spending: [IndexerFixtures.bytes(1)])

        let url = try #require(await transport.requests.first?.url)
        #expect(url.scheme == "https")
        #expect(url.host() == host)
        #expect(url.path() == "/getShieldedTransactionsByNullifiers")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
    }
}
