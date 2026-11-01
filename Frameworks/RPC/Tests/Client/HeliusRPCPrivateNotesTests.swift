import Foundation
import Testing
@testable import RPC

struct HeliusRPCPrivateNotesTests {
    private typealias Fixture = IndexerFixtures

    @Test(arguments: IndexerFixtures.hosts)
    func `Private-note reads go to the network's keyless indexer without the key`(network: Network,
                                                                                 host: String) async throws {
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            let payload = switch route {
            case GetMerkleProofs.method: Fixture.proofs([Fixture.merkleProof(leaf: 7)])
            case GetNonInclusionProofs.method: Fixture.proofs([Fixture.nonInclusionProof(leaf: 5)])
            case GetEncryptedUtxosByTags.method: Fixture.page(in: "matches")
            default: Fixture.page([Fixture.transaction(signature: 1, slot: 10, nullifiers: [2])])
            }
            return try reply(to: request, payload: payload)
        }
        let rpc: any PrivateNoteProviding = HeliusRPC(apiKey: "fixture-key", network: network, transport: transport)

        async let taggedRead = rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        async let spendingRead = rpc.shieldedTransactions(spending: [Fixture.bytes(2)])
        async let includedRead = rpc.merkleProofs(for: [Fixture.bytes(7)], inTree: Fixture.hash(9))
        async let excludedRead = rpc.nonInclusionProofs(for: [Fixture.bytes(5)], inTree: Fixture.hash(9))
        let (tagged, spending, included, excluded) = try await (taggedRead, spendingRead, includedRead, excludedRead)

        #expect(tagged.transactions.map(\.signature) == [Fixture.signature(1)])
        #expect(spending.map(\.signature) == [Fixture.signature(1)])
        #expect(included.map(\.leaf) == [Fixture.bytes(7)])
        #expect(excluded.map(\.nullifier) == [Fixture.bytes(5)])
        let requests = await transport.requests
        #expect(Set(requests.compactMap { $0.url?.lastPathComponent }) == [
            GetShieldedTransactionsByTags.method, GetEncryptedUtxosByTags.method,
            GetShieldedTransactionsByNullifiers.method, GetMerkleProofs.method, GetNonInclusionProofs.method,
        ])
        for request in requests {
            let url = try #require(request.url)
            let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
            let fields = (request.allHTTPHeaderFields ?? [:]).flatMap { [$0.key, $0.value] }
            #expect(url.host() == host)
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
            #expect(!([url.absoluteString, body] + fields).contains { $0.contains("fixture-key") })
        }
    }
}
