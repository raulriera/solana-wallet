import Foundation
import Synchronization
import Testing
@testable import RPC

struct ZolanaProofsTests {
    private typealias Fixture = ProofFixtures

    private static let resolvedTrees = [
        ProverAnswer.tree(),
        ProverAnswer.tree(tree: .string(ProverAnswer.zeroAddress), id: 7, utxoRoot: ProverAnswer.word(0x73),
                          nullifierRoot: ProverAnswer.word(0x74), utxoRootIndex: 9, nullifierRootIndex: 10),
    ]

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
        let transport = prover.transport()

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
        let json = try ProverAnswer.indexed(trees: .array(Self.resolvedTrees))
        let (zolana, transport) = try Self.zolana(body: json)

        let proof = try await zolana.proveTransfer(Fixture.twoTreeRequest())

        #expect(proof == (try JSONDecoder().decode(IndexedTransferProofResponse.self, from: json.data).proof))
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST"])
    }

    @Test
    func `An encrypted refusal surfaces its status without a retry`() async throws {
        let refusal: JSONValue = ["code": "indexer_unavailable", "message": "secret"]
        let (zolana, transport) = try Self.zolana(status: 502, body: refusal)

        await #expect(throws: RPCError.http(statusCode: 502, retryAfter: nil)) {
            try await zolana.proveTransfer(Fixture.indexedRequest())
        }
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `An encrypted success that isn't a proof is a decoding error`() async throws {
        let (zolana, _) = try Self.zolana(body: ProverAnswer.proof())

        await #expect(throws: RPCError.decoding) { try await zolana.proveTransfer(Fixture.indexedRequest()) }
    }

    @Test
    func `A request that the prover can't decrypt surfaces its refusal without attesting again`() async throws {
        let prover = try StubProver { _ in (200, "{}") }
        let transport = StubTransport { request in
            guard request.httpMethod == "POST" else { return try #require(try prover.respond(to: request)) }
            return try httpReply(to: request, body: #"{"code":"tee_decryption_failed"}"#, status: 400)
        }

        await #expect(throws: RPCError.http(statusCode: 400, retryAfter: nil)) {
            try await StubProver.zolana(transport: transport).proveTransfer(Fixture.indexedRequest())
        }
        #expect(await transport.requests.map(\.httpMethod) == ["GET", "POST"])
    }

    private static func zolana(status: Int = 200, body: JSONValue) throws -> (Zolana, StubTransport) {
        let text = try body.json
        let transport = try StubProver { _ in (status, text) }.transport()
        return (StubProver.zolana(transport: transport), transport)
    }
}
