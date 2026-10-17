import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies proof requests on the prover's complete route, the checks and conversion of the
/// prover's responses, and whole proved instructions against an independent implementation, through
/// the real Helius client with local indexer and prover responses.
struct TransactPlanProofTests {
    /// A change that makes a plan's tree witnesses disagree with its inputs.
    enum WitnessEdit: CaseIterable, CustomTestStringConvertible {
        /// The trees in the other order.
        case reordered
        /// The second tree missing.
        case missingTree
        /// The first tree with the second tree's inclusion proofs.
        case crossedProofs

        /// The change's name in test results.
        var testDescription: String { "\(self)" }
    }

    /// Verifies whole proved instructions: the indexer reads of each declared tree, the request that
    /// the prover receives on its complete route, and the instruction built from its response, for
    /// transfers, withdrawals, both, one and two trees, and padding.
    ///
    /// - Parameter vector: A plan, its indexer proofs, its request, the prover's response, and the
    ///   instruction.
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

    /// Verifies that the indexer's proofs give each declared tree the reference's roots and root
    /// positions, and the slots reproduce the reference's public input hash.
    ///
    /// - Parameter vector: A plan and its indexer proofs.
    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Tree witnesses match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let plan = try vector.plan()

        let trees = try Self.witnesses(of: vector)

        #expect(trees.map(\.slot) == (try vector.treeSlots.map { try $0.slot() }))
        #expect(trees.map { [$0.context.utxoTreeRootIndex, $0.context.nullifierTreeRootIndex] } == vector.treeContexts)
        #expect(plan.publicInputs.hash(treeSlots: trees.map(\.slot)) == (try Poseidon.Element(hex: vector.publicInputHash)))
    }

    /// Verifies the conversion of each response: `a` negated and compressed, `b` copied, and `c`
    /// compressed.
    ///
    /// - Parameter vector: A plan and the prover's response.
    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Proofs match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof

        let proof = try vector.plan().proof(from: response)

        var writer = WincodeWriter()
        proof.write(to: &writer)
        #expect(writer.bytes == (try fixtureBytes(vector.proof)))
    }

    /// Verifies that a proof made with another proving key is rejected.
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

    /// Verifies that a proof point with a coordinate at the base field's modulus, and a `b` of
    /// another length, are rejected.
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

    /// Verifies that tree witnesses that don't match the plan's inputs can't form a request: trees
    /// in another order, a missing tree, and a tree whose proofs prove other leaves.
    ///
    /// - Parameter edit: The change to the plan's witnesses.
    /// - Throws: A test failure if a fixture is malformed.
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

    /// Verifies that a nullifier key that isn't the sender's can't request a proof, and that a
    /// proved instruction with it sends no request.
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

    /// Verifies that printing, dumping, and reflecting a request omit its witness, which holds the
    /// nullifier secret and the blinding seed.
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

    /// Decodes a vector's indexer proofs, as the Helius client does, into one witness per declared tree.
    ///
    /// - Parameter vector: A plan and its indexer proofs.
    /// - Returns: The witnesses, in declaration order.
    /// - Throws: A decoding or validation error for a malformed fixture.
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
