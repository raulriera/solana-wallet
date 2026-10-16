import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies proof requests, the checks and conversion of the prover's responses, and whole proved
/// instructions against an independent implementation, through the real Helius client with local
/// responses.
struct TransactPlanProofTests {
    /// A change to a valid prover response that the plan must reject.
    enum ResponseEdit: CaseIterable, CustomTestStringConvertible {
        /// A proving-key digest that isn't the shape's.
        case otherProvingKey
        /// The declared tree's address with another tree's ID.
        case otherTreeID
        /// The declared tree's ID with another address.
        case otherTreeAddress
        /// No resolved tree.
        case missingTree
        /// A UTXO root position one past the history's 500 roots.
        case utxoRootIndexBeyondHistory
        /// The UTXO root position `0xFFFF`, which marks a tree without a UTXO root.
        case absentUTXORoot
        /// A nullifier root position one past the history's 100 roots.
        case nullifierRootIndexBeyondHistory
        /// A UTXO root at or above r.
        case nonCanonicalRoot
        /// A public input hash that the roots don't reproduce.
        case otherPublicInputHash

        /// The rejection that the edit causes.
        var error: TransactPlan.ValidationError {
            switch self {
            case .otherProvingKey: .unexpectedProvingKey
            case .otherTreeID, .otherTreeAddress, .missingTree: .unexpectedTrees
            case .utxoRootIndexBeyondHistory, .absentUTXORoot, .nullifierRootIndexBeyondHistory: .rootIndexOutOfRange
            case .nonCanonicalRoot: .invalidRoot
            case .otherPublicInputHash: .publicInputHashMismatch
            }
        }

        /// The edit's name, in test results.
        var testDescription: String { "\(self)" }

        /// Applies the edit.
        ///
        /// - Parameter proof: A valid response for a plan with one declared tree.
        /// - Returns: The edited response.
        func apply(to proof: TransferProof) -> TransferProof {
            let tree = proof.resolution.trees[0]
            var digest = proof.provingKeyDigest
            var hash = proof.resolution.publicInputHash
            var editedTree = (
                address: tree.address, id: tree.id, utxoRoot: tree.utxoRoot, nullifierRoot: tree.nullifierRoot,
                utxoRootIndex: tree.utxoRootIndex, nullifierRootIndex: tree.nullifierRootIndex
            )
            var trees: [TransferProof.ResolvedTree]?
            switch self {
            case .otherProvingKey: digest[0] ^= 1
            case .otherTreeID: editedTree.id += 1
            case .otherTreeAddress: editedTree.address = "11111111111111111111111111111111"
            case .missingTree: trees = []
            case .utxoRootIndexBeyondHistory: editedTree.utxoRootIndex = 500
            case .absentUTXORoot: editedTree.utxoRootIndex = .max
            case .nullifierRootIndexBeyondHistory: editedTree.nullifierRootIndex = 100
            case .nonCanonicalRoot: editedTree.utxoRoot = [UInt8](repeating: 0xff, count: 32)
            case .otherPublicInputHash: hash[31] ^= 1
            }
            let resolved = trees ?? [TransferProof.ResolvedTree(
                address: editedTree.address, id: editedTree.id, utxoRoot: editedTree.utxoRoot, nullifierRoot: editedTree.nullifierRoot,
                utxoRootIndex: editedTree.utxoRootIndex, nullifierRootIndex: editedTree.nullifierRootIndex
            )]
            return TransferProof(
                a: proof.a, b: proof.b, c: proof.c, provingKeyDigest: digest,
                resolution: TransferProof.Resolution(trees: resolved, publicInputHash: hash)
            )
        }
    }

    /// Verifies whole proved instructions: the request that the prover receives on its indexed
    /// route, and the instruction built from its response, for transfers, withdrawals, both, one
    /// and two trees, and padding.
    ///
    /// - Parameter vector: A plan, its request, the prover's response, and the instruction.
    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Proved instructions match the independent reference`(_ vector: ProofRequestVectors.Transact) async throws {
        let plan = try vector.plan()
        let response = try vector.response.data
        let transport = StubTransport { request in
            let url = try #require(request.url)
            return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }

        let instruction = try await plan.instruction(
            nullifierKey: TransferVectors.sender().nullifierKey, prover: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        )

        let request = try #require(await transport.requests.first)
        let body = try #require(request.httpBody)
        #expect(await transport.requests.count == 1)
        #expect(request.url?.path() == "/v1/zolana/prove/transfer_confidential_\(plan.shape.inputs)_\(plan.shape.outputs)/indexed")
        #expect(request.value(forHTTPHeaderField: "X-Sync") == "true")
        #expect(try JSONValue.decode(body) == vector.request)
        #expect(Array(instruction.data) == (try fixtureBytes(vector.instructionData)))
    }

    /// Verifies the conversion of each response: `a` negated and compressed, `b` copied, `c`
    /// compressed, and the resolved root positions as tree contexts.
    ///
    /// - Parameter vector: A plan and the prover's response.
    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Proofs match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof

        let (proof, treeContexts) = try vector.plan().proof(from: response)

        var writer = WincodeWriter()
        proof.write(to: &writer)
        #expect(writer.bytes == (try fixtureBytes(vector.proof)))
        #expect(treeContexts.map { [$0.utxoTreeRootIndex, $0.nullifierTreeRootIndex] } == vector.treeContexts)
    }

    /// Verifies that a response that doesn't match the plan is rejected.
    ///
    /// - Parameter edit: The change to a valid response.
    @Test(arguments: ResponseEdit.allCases)
    func `Mismatched responses are rejected`(_ edit: ResponseEdit) throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof

        #expect(throws: edit.error) {
            try vector.plan().proof(from: edit.apply(to: response))
        }
    }

    /// Verifies that a response whose two resolved trees are swapped is rejected.
    @Test
    func `Swapped trees are rejected`() throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first { $0.treeSlots.count == 2 })
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof
        let swapped = TransferProof(
            a: response.a, b: response.b, c: response.c, provingKeyDigest: response.provingKeyDigest,
            resolution: TransferProof.Resolution(trees: response.resolution.trees.reversed(), publicInputHash: response.resolution.publicInputHash)
        )

        #expect(throws: TransactPlan.ValidationError.unexpectedTrees) {
            try vector.plan().proof(from: swapped)
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
            TransferProof(a: a, b: b, c: response.c, provingKeyDigest: response.provingKeyDigest, resolution: response.resolution)
        }

        #expect(throws: ProofPoint.ValidationError.invalidCoordinate) {
            try plan.proof(from: edited(TransferProof.G1Point(x: modulus, y: response.a.y), response.b))
        }
        #expect(throws: TransactProof.ValidationError.invalidLength) {
            try plan.proof(from: edited(response.a, Array(response.b.dropLast())))
        }
    }

    /// Verifies that a nullifier key that isn't the sender's can't request a proof.
    @Test
    func `Other nullifier keys are rejected`() throws {
        let plan = try #require(try ProofRequestVectors.load().transacts.first).plan()
        let otherKey = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 1, count: 31)))

        #expect(throws: TransactPlan.ValidationError.foreignNullifierKey) {
            try plan.proofRequest(nullifierKey: otherKey)
        }
    }

    /// Verifies that printing, dumping, and reflecting a request omit its witness, which holds the
    /// nullifier secret and the blinding seed.
    @Test
    func `Request diagnostics omit the witness`() throws {
        let request = try #require(try ProofRequestVectors.load().transacts.first).plan()
            .proofRequest(nullifierKey: TransferVectors.sender().nullifierKey)
        var output = ""
        dump(request, to: &output)

        #expect(String(reflecting: request) == "TransferProofRequest")
        #expect(output == "- TransferProofRequest\n")
        #expect(Mirror(reflecting: request.witness).children.isEmpty)
    }
}
