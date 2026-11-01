import Foundation
import Synchronization
import Testing
@testable import RPC

struct ZolanaProofsTests {
    private typealias Fixture = ProofFixtures

    @Test(arguments: [
        (Network.devnet, "dd73hh473h6ha.cloudfront.net", false, "/prove/transfer_confidential_1_2/indexed"),
        (.mainnet, "d3ky2kt0ntqxt1.cloudfront.net", true, "/prove/transfer_confidential_3_2/indexed"),
    ] as [(Network, String, Bool, String)])
    func `A proof request goes sealed to the shape's indexed route on the network's prover with synchronous delivery`(
        network: Network,
        host: String,
        hasTwoTrees: Bool,
        path: String
    ) async throws {
        let request = try hasTwoTrees ? Fixture.twoTreeRequest() : Fixture.indexedRequest()
        let opened = Mutex<Data?>(nil)
        let prover = try StubProver { body in
            opened.withLock { $0 = body }
            return (503, "{}")
        }
        let transport = StubTransport { try #require(try prover.respond(to: $0)) }

        _ = try? await StubProver.zolana(on: network, transport: transport).proveTransfer(request)

        let post = try #require(await transport.requests.last)
        let url = try #require(post.url)
        #expect(post.httpMethod == "POST")
        #expect(url.host() == host)
        #expect(url.path() == path)
        #expect(url.query() == nil)
        #expect(post.value(forHTTPHeaderField: "X-Sync") == "true")
        let body = try #require(opened.withLock { $0 })
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: AnyHashable]
        #expect(sent == (try Fixture.json(IndexedTransferProofBody(request))))
    }

    @Test
    func `An encrypted success yields the decoded proof and resolution`() async throws {
        let json = Fixture.indexedResponse(trees: Fixture.resolvedTrees)
        let (zolana, transport) = try Self.zolana(body: json)

        let proof = try await zolana.proveTransfer(Fixture.twoTreeRequest())

        #expect(proof == (try JSONDecoder().decode(IndexedTransferProofResponse.self, from: Data(json.utf8)).proof))
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST"])
    }

    @Test(arguments: [
        Array(ProofFixtures.resolvedTrees.reversed()),
        [ProofFixtures.resolvedTrees[0],
         ProofFixtures.resolvedTree(tree: #""\#(ProofFixtures.zeroAddress)""#, id: "8")],
        [ProofFixtures.resolvedTrees[0], ProofFixtures.resolvedTree(id: "7")],
        [ProofFixtures.resolvedTrees[0]],
        ProofFixtures.resolvedTrees + [ProofFixtures.resolvedTree(id: "9")],
        [ProofFixtures.resolvedTrees[0],
         ProofFixtures.resolvedTree(tree: #""\#(ProofFixtures.zeroAddress)""#, id: "7", utxoRootIndex: "65535")],
        [ProofFixtures.resolvedTrees[0],
         ProofFixtures.resolvedTree(tree: #""\#(ProofFixtures.zeroAddress)""#, id: "7", utxoRoot: #""0x0""#,
                                    utxoRootIndex: "65535")],
    ])
    func `A resolution of other trees, in another order, or without a spent tree's state root is refused`(
        trees: [String]
    ) async throws {
        let (zolana, _) = try Self.zolana(body: Fixture.indexedResponse(trees: trees))

        await #expect(throws: RPCError.invalidResponse(.mismatchedResolution)) {
            try await zolana.proveTransfer(Fixture.twoTreeRequest())
        }
    }

    @Test
    func `An encrypted refusal surfaces its status without a retry`() async throws {
        let refusal = #"{"code":"indexer_unavailable","message":"secret"}"#
        let (zolana, transport) = try Self.zolana(status: 502, body: refusal)

        await #expect(throws: RPCError.http(statusCode: 502, retryAfter: nil)) {
            try await zolana.proveTransfer(Fixture.indexedRequest())
        }
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `An encrypted success that isn't a proof is a decoding error`() async throws {
        let (zolana, _) = try Self.zolana(body: Fixture.response())

        await #expect(throws: RPCError.decoding) { try await zolana.proveTransfer(Fixture.indexedRequest()) }
    }

    @Test
    func `A stale key attests again and resends the request once`() async throws {
        let (zolana, transport) = try Self.zolana(staleRefusals: 1, body: Fixture.indexedResponse())

        let proof = try await zolana.proveTransfer(Fixture.indexedRequest())

        #expect(proof.resolution.publicInputHash == Fixture.field(0x99))
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST", "GET", "POST"])
    }

    @Test
    func `A key that is stale again after a new attestation surfaces as stale`() async throws {
        let (zolana, transport) = try Self.zolana(staleRefusals: 2, body: Fixture.indexedResponse())

        await #expect(throws: RPCError.invalidResponse(.staleProverKey)) {
            try await zolana.proveTransfer(Fixture.indexedRequest())
        }
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST", "GET", "POST"])
    }

    private static func zolana(staleRefusals: Int = 0, status: Int = 200, body: String) throws
        -> (Zolana, StubTransport) {
        let prover = try StubProver { _ in (status, body) }
        let refusals = Mutex(staleRefusals)
        let transport = StubTransport { request in
            let isStale = request.httpMethod == "POST" && refusals.withLock { remaining in
                defer { remaining -= 1 }
                return remaining > 0
            }
            guard isStale else { return try #require(try prover.respond(to: request)) }
            return try httpReply(to: request, body: #"{"code":"tee_decryption_failed"}"#, status: 400)
        }
        return (StubProver.zolana(transport: transport), transport)
    }
}
