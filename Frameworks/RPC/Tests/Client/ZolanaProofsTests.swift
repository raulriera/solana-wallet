import Foundation
import Synchronization
import Testing
@testable import RPC

struct ZolanaProofsTests {
    enum Answer: Sendable {
        case encrypted(status: Int, body: String)
        case stale
    }

    private typealias Fixture = ProofFixtures

    private let prover: TestProver

    init() throws {
        prover = try TestProver(vectors: EncryptedProverVectors.load())
    }

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
        let (zolana, transport) = zolana(on: network, answering: [.encrypted(status: 503, body: "{}")])

        _ = try? await zolana.proveTransfer(request)

        let post = try #require(await transport.requests.last)
        let url = try #require(post.url)
        #expect(post.httpMethod == "POST")
        #expect(url.host() == host)
        #expect(url.path() == path)
        #expect(url.query() == nil)
        #expect(post.value(forHTTPHeaderField: "X-Sync") == "true")
        #expect(post.value(forHTTPHeaderField: "Zolana-Tee") == "v1")
        let sent = try JSONSerialization.jsonObject(with: try prover.open(post).body) as? [String: AnyHashable]
        #expect(sent == (try Fixture.json(IndexedTransferProofBody(request))))
    }

    @Test
    func `An encrypted success yields the decoded proof and resolution`() async throws {
        let json = Fixture.indexedResponse(trees: Fixture.resolvedTrees)
        let (zolana, transport) = zolana(answering: [.encrypted(status: 200, body: json)])

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
        let (zolana, _) = zolana(answering: [.encrypted(status: 200, body: Fixture.indexedResponse(trees: trees))])

        await #expect(throws: RPCError.invalidResponse(.mismatchedResolution)) {
            try await zolana.proveTransfer(Fixture.twoTreeRequest())
        }
    }

    @Test
    func `An encrypted refusal surfaces its status without a retry`() async throws {
        let (zolana, transport) = zolana(answering: [
            .encrypted(status: 502, body: #"{"code":"indexer_unavailable","message":"secret"}"#),
        ])

        await #expect(throws: RPCError.http(statusCode: 502, retryAfter: nil)) {
            try await zolana.proveTransfer(Fixture.indexedRequest())
        }
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `An encrypted success that isn't a proof is a decoding error`() async throws {
        let (zolana, _) = zolana(answering: [.encrypted(status: 200, body: Fixture.response())])

        await #expect(throws: RPCError.decoding) { try await zolana.proveTransfer(Fixture.indexedRequest()) }
    }

    @Test
    func `A stale key attests again and resends the request once`() async throws {
        let (zolana, transport) = zolana(answering: [
            .stale, .encrypted(status: 200, body: Fixture.indexedResponse()),
        ])

        let proof = try await zolana.proveTransfer(Fixture.indexedRequest())

        #expect(proof.resolution.publicInputHash == Fixture.field(0x99))
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST", "GET", "POST"])
    }

    @Test
    func `A key that is stale again after a new attestation surfaces as stale`() async throws {
        let (zolana, transport) = zolana(answering: [.stale, .stale])

        await #expect(throws: RPCError.invalidResponse(.staleProverKey)) {
            try await zolana.proveTransfer(Fixture.indexedRequest())
        }
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST", "GET", "POST"])
    }

    private func zolana(on network: Network = .devnet, answering answers: [Answer]) -> (Zolana, StubTransport) {
        let remaining = Mutex(answers)
        let attestation = Fixture.attestation(of: prover.publicKey)
        let transport = StubTransport { [prover] request in
            guard request.httpMethod == "POST" else { return try httpReply(to: request, body: attestation) }
            switch remaining.withLock({ $0.removeFirst() }) {
            case .encrypted(let status, let body):
                return try prover.open(request).answer(status: status, body: Data(body.utf8))
            case .stale:
                return try httpReply(to: request, body: #"{"code":"tee_decryption_failed"}"#, status: 400)
            }
        }
        return (Zolana(network: network, transport: transport, verify: Fixture.claimedKey), transport)
    }
}
