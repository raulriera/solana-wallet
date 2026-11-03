import RPC
import Testing

struct IndexedTransferProofRequestTests {
    struct Refusal: Sendable {
        let error: IndexedTransferProofRequest.ValidationError
        let make: @Sendable () throws -> Void

        init(_ error: IndexedTransferProofRequest.ValidationError, _ make: @escaping @Sendable () throws -> Void) {
            self.error = error
            self.make = make
        }
    }

    private typealias Fixture = ProofFixtures

    @Test(arguments: [
        { try ProofFixtures.indexedRequest() },
        { try ProofFixtures.twoTreeRequest() },
        {
            try ProofFixtures.indexedRequest(
                publicInputs: ProofFixtures.publicInputs(replacing: 16, with: fieldElement(0x85))
            )
        },
    ] as [@Sendable () throws -> IndexedTransferProofRequest])
    func `Requests that zolana's clients accept build`(make: @Sendable () throws -> IndexedTransferProofRequest) {
        #expect(throws: Never.self) { try make() }
    }

    @Test(arguments: [
        Refusal(.invalidLength) { _ = try ProofFixtures.indexedTree(address: Array(repeating: 1, count: 31)) },
        Refusal(.invalidLength) {
            _ = try ProofFixtures.indexedInput(commitment: Array(repeating: 1, count: 33))
        },
        Refusal(.invalidLength) {
            _ = try IndexedTransferProofRequest.UTXO(
                domain: [3], owner: fieldElement(0), asset: fieldElement(0),
                amount: fieldElement(0), blinding: fieldElement(0), dataHash: fieldElement(0),
                ringDataHash: fieldElement(0), ringProgramID: fieldElement(0)
            )
        },
        Refusal(.invalidLength) {
            _ = try IndexedTransferProofRequest.Output(
                utxo: ProofFixtures.utxo(), isDummy: false, hash: [], ownerPublicKeyHash: fieldElement(1),
                nullifierPublicKey: fieldElement(1)
            )
        },
        Refusal(.invalidLength) { _ = try ProofFixtures.indexedRequest(blindingSeed: [1]) },
        Refusal(.invalidLength) {
            _ = try ProofFixtures.indexedRequest(publicInputs: ProofFixtures.publicInputs(replacing: 0, with: [1]))
        },
        Refusal(.invalidCount) { _ = try ProofFixtures.indexedRequest(trees: []) },
        Refusal(.invalidCount) {
            _ = try ProofFixtures.indexedRequest(trees: [0, 1, 2].map { try ProofFixtures.indexedTree(id: $0) })
        },
        Refusal(.invalidCount) { _ = try ProofFixtures.indexedRequest(inputs: []) },
        Refusal(.invalidCount) {
            _ = try ProofFixtures.indexedRequest(publicInputs: Array(ProofFixtures.publicInputs().prefix(16)))
        },
        Refusal(.zeroBlindingSeed) { _ = try ProofFixtures.indexedRequest(blindingSeed: fieldElement(0)) },
        Refusal(.unsupportedCache) {
            _ = try ProofFixtures.indexedRequest(
                publicInputs: ProofFixtures.publicInputs(replacing: 15, with: fieldElement(1))
            )
        },
        Refusal(.duplicateTree) {
            _ = try ProofFixtures.indexedRequest(
                trees: [ProofFixtures.indexedTree(), ProofFixtures.indexedTree(address: fieldElement(9))],
                inputs: [ProofFixtures.indexedInput(), ProofFixtures.indexedInput(treeSlot: 1)]
            )
        },
        Refusal(.duplicateTree) {
            _ = try ProofFixtures.indexedRequest(
                trees: [ProofFixtures.indexedTree(), ProofFixtures.indexedTree(id: 1)],
                inputs: [ProofFixtures.indexedInput(), ProofFixtures.indexedInput(treeSlot: 1)]
            )
        },
        Refusal(.invalidTreeSlot) {
            _ = try ProofFixtures.indexedRequest(inputs: [ProofFixtures.indexedInput(treeSlot: 1)])
        },
        Refusal(.invalidTreeSlot) {
            _ = try ProofFixtures.indexedRequest(
                inputs: [ProofFixtures.indexedInput(isDummy: true, commitment: nil), ProofFixtures.indexedInput()]
            )
        },
        Refusal(.unusedTree) {
            _ = try ProofFixtures.indexedRequest(
                trees: [ProofFixtures.indexedTree(), ProofFixtures.indexedTree(id: 1, address: fieldElement(9))]
            )
        },
        Refusal(.invalidNullifier) {
            _ = try ProofFixtures.indexedInput(isDummy: true, nullifier: fieldElement(0), commitment: nil)
        },
        Refusal(.invalidNullifier) {
            _ = try ProofFixtures.indexedInput(nullifier: fixtureBytes(ProofFixtures.fieldOrder))
        },
        Refusal(.invalidCommitment) { _ = try ProofFixtures.indexedInput(commitment: nil) },
        Refusal(.invalidCommitment) { _ = try ProofFixtures.indexedInput(isDummy: true) },
        Refusal(.invalidCommitment) {
            _ = try ProofFixtures.indexedInput(commitment: fixtureBytes(ProofFixtures.fieldOrder))
        },
        Refusal(.nonCanonicalPublicInput) {
            _ = try ProofFixtures.indexedRequest(
                publicInputs: ProofFixtures.publicInputs(replacing: 0, with: fixtureBytes(ProofFixtures.fieldOrder))
            )
        },
    ])
    func `Requests that zolana's clients refuse throw their validation error`(refusal: Refusal) {
        #expect(throws: refusal.error) { try refusal.make() }
    }

    @Test
    func `Descriptions reveal no witness values`() throws {
        let request = try Fixture.indexedRequest()
        var dump = ""
        Swift.dump(request, to: &dump)
        Swift.dump(request.inputs, to: &dump)
        Swift.dump(request.outputs, to: &dump)

        let text = [String(describing: request), String(reflecting: request), String(describing: request.inputs[0]),
                    String(reflecting: request.inputs[0].utxo), String(reflecting: request.outputs[0]), dump]
            .joined(separator: "\n")

        #expect(["161", "177", "193", "209", "225", "a1", "b1", "c1", "d1", "e1"].allSatisfy { !text.contains($0) })
    }
}
