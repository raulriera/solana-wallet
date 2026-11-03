import Encoding
import Testing
@testable import Privacy
@testable import RPC

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct ProverProvingKeysLiveTests {
    @Test(arguments: Network.allCases)
    func `The network's prover serves the pinned proving keys`(network: Network) async throws {
        let catalog = try await Zolana(network: network).prover.get(
            at: "proving-keys", query: [], maximumLength: 1_048_576, decoding: ProvingKeyCatalog.self
        )
        let served = Dictionary(
            catalog.keys.compactMap { key in
                key.artifacts.first { $0.format == "gnark" }.flatMap { Hex.decode($0.sha256) }.map { (key.name, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        for shape in Shape.supported {
            let name = "transfer_confidential_\(shape.inputs)_\(shape.outputs).key"
            #expect(served[name] == shape.provingKeyDigest, "\(name)")
        }
    }

    private struct ProvingKeyCatalog: Decodable, Sendable {
        struct Key: Decodable, Sendable {
            struct Artifact: Decodable, Sendable {
                let format: String
                let sha256: String
            }

            let name: String
            let artifacts: [Artifact]
        }

        let keys: [Key]
    }
}
