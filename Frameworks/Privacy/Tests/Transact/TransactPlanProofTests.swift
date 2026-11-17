import CryptoKit
import Foundation
import ModularArithmetic
import Synchronization
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct TransactPlanProofTests {
    private static let pathKeys: Set = [
        "statePathElements", "statePathIndex", "nullifierLowValue", "nullifierNextValue", "nullifierLowPathElements",
        "nullifierLowPathIndex",
    ]

    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Proved instructions match the independent reference`(_ vector: ProofRequestVectors.Transact) async throws {
        let plan = try vector.plan()
        let answer = try Self.answer(to: vector)
        let opened = Mutex<Data?>(nil)
        let prover = try StubProver { body in
            opened.withLock { $0 = body }
            return (200, answer)
        }
        let transport = prover.transport()
        let complete = try JSONDecoder().decode(CompleteBody.self, from: vector.request.data)

        let instruction = try await plan.instruction(
            nullifierKey: TransferVectors.sender().nullifierKey, prover: StubProver.zolana(transport: transport)
        )

        let sent = try #require(opened.withLock { $0 })
        let body = try JSONValue.decode(sent)
        let route = "/prove/transfer_confidential_\(plan.shape.inputs)_\(plan.shape.outputs)/indexed"
        #expect(await transport.requests.last?.url?.path() == route)
        #expect(body.member("prepared") == (try Self.prepared(from: vector.request)))
        #expect(body.member("trees") == (try Self.trees(of: vector)))
        #expect(body.member("inputs") == (try Self.lookups(of: vector, inputs: complete.inputs)))
        let publicInputs = try JSONDecoder().decode(Envelope.self, from: sent).publicInputs.map(FieldHex.decode)
        #expect(publicInputs == (try vector.publicInputs.map(fixtureBytes)))
        #expect(Array(instruction.data) == (try fixtureBytes(vector.instructionData)))
    }

    @Test
    func `Proofs against another public input hash are rejected`() async throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let answer = try Self.answer(to: vector, publicInputHash: fieldElement(1))
        let transport = try StubProver { _ in (200, answer) }.transport()

        await #expect(throws: TransactPlan.ValidationError.mismatchedPublicInputHash) {
            try await vector.plan().instruction(
                nullifierKey: TransferVectors.sender().nullifierKey, prover: StubProver.zolana(transport: transport)
            )
        }
    }

    @Test
    func `Proofs of another proving key are rejected`() throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let response = try JSONDecoder().decode(TransferProofResponse.self, from: vector.response.data).proof
        var digest = response.provingKeyDigest
        digest[0] ^= 1

        #expect(throws: TransactPlan.ValidationError.unexpectedProvingKey) {
            try vector.plan().proof(
                from: TransferProof(a: response.a, b: response.b, c: response.c, provingKeyDigest: digest)
            )
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

    @Test
    func `Other nullifier keys are rejected`() async throws {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        let plan = try vector.plan()
        let otherKey = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 1, count: 31)))
        let transport = StubTransport { _ in throw CancellationError() }

        #expect(throws: TransactPlan.ValidationError.foreignNullifierKey) {
            try plan.proofRequest(nullifierKey: otherKey)
        }
        await #expect(throws: TransactPlan.ValidationError.foreignNullifierKey) {
            try await plan.instruction(nullifierKey: otherKey, prover: StubProver.zolana(transport: transport))
        }
        #expect(await transport.requests.isEmpty)
    }

    private static func answer(to vector: ProofRequestVectors.Transact, publicInputHash: [UInt8]? = nil) throws
        -> String {
        let addresses = try addresses(of: vector)
        let trees = try vector.treeSlots.indices.map { index in
            let (slot, context) = (vector.treeSlots[index], vector.treeContexts[index])
            return ProverAnswer.tree(
                tree: addresses[index], id: .number(Double(slot.id)),
                utxoRoot: ProverAnswer.word(try fixtureBytes(slot.utxoRoot)),
                nullifierRoot: ProverAnswer.word(try fixtureBytes(slot.nullifierRoot)),
                utxoRootIndex: .number(Double(context[0])), nullifierRootIndex: .number(Double(context[1]))
            )
        }
        return try ProverAnswer.indexed(
            proof: vector.response, trees: .array(trees),
            publicInputHash: ProverAnswer.word(publicInputHash ?? fixtureBytes(vector.publicInputHash))
        ).json
    }

    private static func addresses(of vector: ProofRequestVectors.Transact) throws -> [JSONValue] {
        try vector.merkleProofs.map { try #require($0.first?.member("merkleContext")?.member("tree")) }
    }

    private static func trees(of vector: ProofRequestVectors.Transact) throws -> JSONValue {
        .array(zip(vector.treeSlots, try addresses(of: vector)).map { slot, tree in
            .object(["tree": tree, "id": .number(Double(slot.id))])
        })
    }

    private static func lookups(of vector: ProofRequestVectors.Transact, inputs: [CompleteBody.Input]) throws
        -> JSONValue {
        var leaves = vector.merkleProofs.map { $0.compactMap { $0.member("leaf") }[...] }
        return .array(try inputs.map { input in
            let slot = try #require(Int(input.treeSlot.dropFirst(2), radix: 16))
            let commitment: JSONValue
            if input.isDummy == "0x1" {
                commitment = .null
            } else {
                let leaf = leaves[slot].popFirst()
                commitment = try #require(leaf)
            }
            return .object(["treeSlot": .number(Double(slot)), "commitment": commitment])
        })
    }

    private static func prepared(from request: JSONValue) throws -> JSONValue {
        guard case .object(var fields) = request, case .array(let inputs)? = fields["inputs"] else {
            return try #require(nil as JSONValue?)
        }
        fields["treeSlots"] = nil
        fields["publicInputHash"] = nil
        fields["inputs"] = .array(inputs.map { input in
            guard case .object(let members) = input else { return input }
            return .object(members.filter { !pathKeys.contains($0.key) })
        })
        return .object(fields)
    }
}

private struct CompleteBody: Decodable {
    struct Input: Decodable {
        let isDummy: String
        let treeSlot: String
    }

    let inputs: [Input]
}

private struct Envelope: Decodable {
    let publicInputs: [String]
}
