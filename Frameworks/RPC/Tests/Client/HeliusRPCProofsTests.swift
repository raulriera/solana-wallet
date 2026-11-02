import Foundation
import Synchronization
import Testing
@testable import RPC

struct HeliusRPCProofsTests {
    private typealias Fixture = ProofFixtures

    @Test
    func `Proofs forward to the keyless Solana Rings client without the key`() async throws {
        let opened = Mutex<[Data]>([])
        let prover = try StubProver { body in
            opened.withLock { $0.append(body) }
            return (200, try ProverAnswer.indexed().json)
        }
        let transport = prover.transport()
        let provider: any ProofProviding = HeliusRPC(
            apiKey: "fixture-key", network: .devnet, transport: transport,
            zolana: StubProver.zolana(transport: transport)
        )

        let proof = try await provider.proveTransfer(Fixture.indexedRequest())

        #expect(proof.resolution.publicInputHash == fieldElement(0x99))
        for request in await transport.requests {
            let url = try #require(request.url)
            let fields = (request.allHTTPHeaderFields ?? [:]).flatMap { [$0.key, $0.value] }
            #expect(!([url.absoluteString] + fields).contains { $0.contains("fixture-key") })
        }
        let bodies = opened.withLock { $0 }
        #expect(bodies.count == 1)
        #expect(!bodies.contains { String(decoding: $0, as: UTF8.self).contains("fixture-key") })
    }
}
