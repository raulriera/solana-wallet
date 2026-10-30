import Encoding
import Foundation
import Testing
@testable import RPC

struct HeliusRPCMerkleProofsTests {
    private typealias Fixture = IndexerFixtures

    @Test(arguments: [(Network.mainnet, "mainnet.helius-rpc.com"), (.devnet, "devnet.helius-rpc.com")])
    func `Proof reads post to each method's route below the gateway`(network: Network, host: String) async throws {
        let transport = StubTransport { request in
            let (route, params) = try Fixture.call(request)
            let leaves = try #require(params["leaves"] as? [String])
            let bytes = try leaves.map { try #require(Base58.decode($0, byteCount: 32)?.first) }
            let proofs = route == GetMerkleProofs.method ? bytes.map { Fixture.merkleProof(leaf: $0) }
                : bytes.map { Fixture.nonInclusionProof(leaf: $0) }
            return try reply(to: request, payload: Fixture.proofs(proofs))
        }
        let rpc: any PrivateNoteProviding = HeliusRPC(apiKey: "fixture-key", network: network, transport: transport)

        let included = try await rpc.merkleProofs(for: [Fixture.bytes(7), Fixture.bytes(8)], inTree: Fixture.hash(9))
        let excluded = try await rpc.nonInclusionProofs(for: [Fixture.bytes(5)], inTree: Fixture.hash(9))

        #expect(included.map(\.leaf) == [Fixture.bytes(7), Fixture.bytes(8)])
        #expect(excluded.map(\.nullifier) == [Fixture.bytes(5)])
        let requests = await transport.requests
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://\(host)/v1/zolana/getMerkleProofs?api-key=fixture-key",
            "https://\(host)/v1/zolana/getNonInclusionProofs?api-key=fixture-key",
        ])
        let bodies = try requests.map(requestBody)
        #expect(bodies.map { $0["method"] as? String } == [GetMerkleProofs.method, GetNonInclusionProofs.method])
        #expect(bodies.map { $0["params"] as? [String: AnyHashable] } == [
            ["treeAccount": Fixture.hash(9), "leaves": [Fixture.hash(7), Fixture.hash(8)]],
            ["treeAccount": Fixture.hash(9), "leaves": [Fixture.hash(5)]],
        ])
    }

    @Test(arguments: [
        [IndexerFixtures.merkleProof(leaf: 7), IndexerFixtures.merkleProof(leaf: 6)],
        [IndexerFixtures.merkleProof(leaf: 8), IndexerFixtures.merkleProof(leaf: 7)],
        [IndexerFixtures.merkleProof(leaf: 7)],
        [IndexerFixtures.merkleProof(leaf: 7), IndexerFixtures.merkleProof(leaf: 8), IndexerFixtures.merkleProof(leaf: 8)],
        [IndexerFixtures.merkleProof(leaf: 7), IndexerFixtures.merkleProof(leaf: 8, tree: IndexerFixtures.hash(4))],
    ])
    func `Proofs that don't answer the request are rejected`(proofs: [String]) async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.proofs(proofs)) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedProofs)) {
            try await rpc.merkleProofs(for: [Fixture.bytes(7), Fixture.bytes(8)], inTree: Fixture.hash(9))
        }
    }

    @Test
    func `Non-inclusion proofs of other nullifiers are rejected`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.proofs([Fixture.nonInclusionProof(leaf: 6)])) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedProofs)) {
            try await rpc.nonInclusionProofs(for: [Fixture.bytes(5)], inTree: Fixture.hash(9))
        }
    }

    @Test
    func `Invalid or empty reads send nothing`() async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let tree = Fixture.hash(9)

        #expect(try await rpc.merkleProofs(for: [], inTree: tree).isEmpty)
        #expect(try await rpc.nonInclusionProofs(for: [], inTree: tree).isEmpty)
        await #expect(throws: PrivateNoteError.invalidLeaf) { try await rpc.merkleProofs(for: [[1]], inTree: tree) }
        await #expect(throws: PrivateNoteError.invalidNullifier) { try await rpc.nonInclusionProofs(for: [[1]], inTree: tree) }
        await #expect(throws: PrivateNoteError.invalidTree) {
            try await rpc.merkleProofs(for: [Fixture.bytes(7)], inTree: "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC")
        }
        await #expect(throws: PrivateNoteError.tooManyLeaves) {
            try await rpc.nonInclusionProofs(for: Array(repeating: Fixture.bytes(5), count: 1_001), inTree: tree)
        }
        #expect(await transport.requests.isEmpty)
    }
}
