import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

struct TransactPlanProofTests {
    enum WitnessEdit: CaseIterable, CustomTestStringConvertible {
        case reordered
        case missingTree
        case crossedProofs

        var testDescription: String { "\(self)" }
    }

    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Proved instructions match the independent reference`(_ vector: ProofRequestVectors.Transact) async throws {
        let plan = try vector.plan()
        let transport = StubTransport { request in
            switch request.url?.lastPathComponent {
            case GetMerkleProofs.method: return try IndexerResponses.proofs(from: vector.merkleProofs, answering: request)
            case GetNonInclusionProofs.method: return try IndexerResponses.proofs(from: vector.nonInclusionProofs, answering: request)
            default:
                let url = try #require(request.url)
                return (try vector.response.data,
                        try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }
        }

        let instruction = try await plan.instruction(
            nullifierKey: TransferVectors.sender().nullifierKey, provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        )

        let requests = await transport.requests
        let proofRequests = requests.filter { $0.url?.path() == "/v1/zolana/prove" }
        let request = try #require(proofRequests.first)
        #expect(proofRequests.count == 1)
        #expect(requests.count == 1 + 2 * vector.treeSlots.count)
        #expect(request.value(forHTTPHeaderField: "X-Sync") == "true")
        #expect(try JSONValue.decode(#require(request.httpBody)) == vector.request)
        #expect(Array(instruction.data) == (try fixtureBytes(vector.instructionData)))
    }

    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Tree witnesses match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let plan = try vector.plan()

        let trees = try Self.witnesses(of: vector)

        #expect(trees.map(\.slot) == (try vector.treeSlots.map { try $0.slot() }))
        #expect(trees.map { [$0.context.utxoTreeRootIndex, $0.context.nullifierTreeRootIndex] } == vector.treeContexts)
        #expect(plan.publicInputs.hash(treeSlots: trees.map(\.slot)) == (try Poseidon.Element(hex: vector.publicInputHash)))
    }

    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Proofs match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof

        let proof = try vector.plan().proof(from: response)

        var writer = WincodeWriter()
        proof.write(to: &writer)
        #expect(writer.bytes == (try fixtureBytes(vector.proof)))
    }

    @Test
    func `Proofs of another proving key are rejected`() throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof
        var digest = response.provingKeyDigest
        digest[0] ^= 1

        #expect(throws: TransactPlan.ValidationError.unexpectedProvingKey) {
            try vector.plan().proof(from: TransferProof(a: response.a, b: response.b, c: response.c, provingKeyDigest: digest))
        }
    }

    @Test
    func `Malformed proof points are rejected`() throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let plan = try vector.plan()
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof
        let modulus = try fixtureBytes("30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
        let edited = { (a: TransferProof.G1Point, b: [UInt8]) in
            TransferProof(a: a, b: b, c: response.c, provingKeyDigest: response.provingKeyDigest)
        }

        #expect(throws: ProofPoint.ValidationError.invalidCoordinate) {
            try plan.proof(from: edited(TransferProof.G1Point(x: modulus, y: response.a.y), response.b))
        }
        #expect(throws: TransactProof.ValidationError.invalidLength) {
            try plan.proof(from: edited(response.a, Array(response.b.dropLast())))
        }
    }

    @Test(arguments: WitnessEdit.allCases)
    func `Witnesses of other inputs are rejected`(_ edit: WitnessEdit) throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first { $0.treeSlots.count == 2 })
        let plan = try vector.plan()
        let key = try TransferVectors.sender().nullifierKey
        let trees = try Self.witnesses(of: vector)
        let edited: [TransactPlan.TreeWitness] = switch edit {
        case .reordered: trees.reversed()
        case .missingTree: [trees[0]]
        case .crossedProofs: [
            try TransactPlan.TreeWitness(treeID: trees[0].slot.treeID, inclusionProofs: trees[1].inclusionProofs,
                                         nonInclusionProofs: trees[0].nonInclusionProofs),
            trees[1],
        ]
        }

        #expect(throws: TransactPlan.ValidationError.inconsistentProofs) {
            try plan.proofRequest(nullifierKey: key, trees: edited)
        }
    }

    @Test
    func `Other nullifier keys are rejected`() async throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let plan = try vector.plan()
        let otherKey = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 1, count: 31)))
        let transport = StubTransport { _ in throw CancellationError() }

        #expect(throws: TransactPlan.ValidationError.foreignNullifierKey) {
            try plan.proofRequest(nullifierKey: otherKey, trees: Self.witnesses(of: vector))
        }
        await #expect(throws: TransactPlan.ValidationError.foreignNullifierKey) {
            try await plan.instruction(nullifierKey: otherKey, provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `Request diagnostics omit the witness`() throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let request = try vector.plan().proofRequest(nullifierKey: TransferVectors.sender().nullifierKey, trees: Self.witnesses(of: vector))
        var output = ""
        dump(request, to: &output)

        #expect(String(reflecting: request) == "TransferProofRequest")
        #expect(output == "- TransferProofRequest\n")
        #expect(Mirror(reflecting: request.witness).children.isEmpty)
    }

    private static func witnesses(of vector: ProofRequestVectors.Transact) throws -> [TransactPlan.TreeWitness] {
        try zip(vector.treeSlots, zip(vector.merkleProofs, vector.nonInclusionProofs)).map { slot, proofs in
            try TransactPlan.TreeWitness(
                treeID: slot.id,
                inclusionProofs: JSONDecoder().decode(MerkleProofList.self, from: JSONValue.object(["proofs": .array(proofs.0)]).data)
                    .proofs.map(\.proof),
                nonInclusionProofs: JSONDecoder().decode(NonInclusionProofList.self, from: JSONValue.object(["proofs": .array(proofs.1)]).data)
                    .proofs.map(\.proof)
            )
        }
    }
}
