import Foundation
import Synchronization
import Testing
import Transactions
@testable import Privacy
@testable import RPC

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct ProverIndexedLiveTests {
    @Test(arguments: Network.allCases)
    func `A commitment outside the tree comes back as an encrypted refusal`(network: Network) async throws {
        let answerVersions = Mutex<[String?]>([])
        let transport = StubTransport { request in
            let (data, response) = try await URLSessionTransport().data(for: request)
            let version = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Spr-Tee")
            answerVersions.withLock { $0.append(version) }
            return (data, response)
        }
        let zolana = try LiveClients.rings(network: network, transport: transport)
        let request = try Self.request()

        let error = try await #require(throws: RPCError.self) { try await zolana.proveTransfer(request) }

        #expect(error.statusCode.map((400..<600).contains) == true, "Received \(String(describing: error))")
        #expect(await transport.requests.last?.url?.path() == "/prove/transfer_confidential_1_2/indexed")
        #expect(answerVersions.withLock { $0.last } == "v1")
    }

    private static func request() throws -> IndexedTransferProofRequest {
        let zero = fieldElement(0)
        let utxo = try IndexedTransferProofRequest.UTXO(
            domain: fieldElement(3), owner: randomFieldElement(), asset: zero, amount: fieldElement(1),
            blinding: randomFieldElement(), dataHash: zero, ringDataHash: zero, ringProgramID: zero
        )
        let padding = try IndexedTransferProofRequest.UTXO(
            domain: fieldElement(1), owner: zero, asset: zero, amount: zero, blinding: randomFieldElement(),
            dataHash: zero, ringDataHash: zero, ringProgramID: zero
        )
        var publicInputs = (0..<17).map { _ in randomFieldElement() }
        publicInputs[15] = zero
        return try IndexedTransferProofRequest(
            trees: [.init(id: 0, address: try ShieldedPool.tree(id: 0).bytes)],
            inputs: [
                .init(utxo: utxo, isDummy: false, treeSlot: 0, nullifier: randomFieldElement(),
                      ownerPublicKeyHash: randomFieldElement(), nullifierSecret: randomFieldElement(),
                      commitment: randomFieldElement()),
            ],
            outputs: [
                .init(utxo: utxo, isDummy: false, hash: randomFieldElement(), ownerPublicKeyHash: randomFieldElement(),
                      nullifierPublicKey: randomFieldElement()),
                .init(utxo: padding, isDummy: true, hash: randomFieldElement(),
                      ownerPublicKeyHash: randomFieldElement(), nullifierPublicKey: zero),
            ],
            publicInputs: publicInputs,
            outputTreeID: 0,
            blindingSeed: randomFieldElement(),
            publicAssets: [zero, zero, zero],
            publicAmounts: [zero, zero, zero],
            ringProgramID: zero,
            signerPublicKeyHashes: [randomFieldElement(), zero],
            inputFlags: fieldElement(1),
            publishedOutputOwnerPublicKeyHashes: [randomFieldElement(), randomFieldElement()]
        )
    }
}
