import ModularArithmetic
@testable import Privacy
import RPC
import Testing

struct TransactPlanTreeWitnessTests {
    enum Edit: CaseIterable, CustomTestStringConvertible {
        case noInclusionProof
        case noNonInclusionProof
        case otherUTXORoot
        case otherUTXORootIndex
        case otherNullifierRoot
        case otherNullifierRootIndex
        case utxoRootIndexBeyondHistory
        case nullifierRootIndexBeyondHistory
        case nonCanonicalUTXORoot
        case nonCanonicalNullifierRoot
        case lowElementAtNullifier
        case highElementAtNullifier
        case swappedElements

        var error: TransactPlan.ValidationError {
            switch self {
            case .noInclusionProof, .noNonInclusionProof, .otherUTXORoot, .otherUTXORootIndex, .otherNullifierRoot,
                 .otherNullifierRootIndex: .inconsistentProofs
            case .utxoRootIndexBeyondHistory, .nullifierRootIndexBeyondHistory: .rootIndexOutOfRange
            case .nonCanonicalUTXORoot, .nonCanonicalNullifierRoot: .invalidRoot
            case .lowElementAtNullifier, .highElementAtNullifier, .swappedElements: .invalidNonInclusionProof
            }
        }

        var testDescription: String { "\(self)" }
    }

    private static let modulus = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

    @Test
    func `Witnesses take their roots and positions from the proofs`() throws {
        let witness = try TransactPlan.TreeWitness(
            treeID: 4, inclusionProofs: [Self.inclusion(), Self.inclusion(leaf: 0x12)],
            nonInclusionProofs: [Self.nonInclusion(), Self.nonInclusion(nullifier: 0x51)]
        )

        #expect(witness.slot == PublicInputs.TreeSlot(treeID: 4, utxoRoot: Poseidon.Element(UInt64(0x71)),
                                                      nullifierRoot: Poseidon.Element(UInt64(0x72))))
        #expect(witness.context == TreeContext(utxoTreeRootIndex: 499, nullifierTreeRootIndex: 99))
        #expect(witness.inclusionProofs.map(\.leaf) == [Self.field(0x11), Self.field(0x12)])
        #expect(witness.nonInclusionProofs.map(\.nullifier) == [Self.field(0x50), Self.field(0x51)])
    }

    @Test(arguments: Edit.allCases)
    func `Invalid proofs are rejected`(_ edit: Edit) throws {
        let r = try fixtureBytes(Self.modulus)
        var inclusionProofs = [try Self.inclusion()]
        var nonInclusionProofs = [try Self.nonInclusion()]
        switch edit {
        case .noInclusionProof: inclusionProofs = []
        case .noNonInclusionProof: nonInclusionProofs = []
        case .otherUTXORoot: inclusionProofs.append(try Self.inclusion(root: Self.field(0x73)))
        case .otherUTXORootIndex: inclusionProofs.append(try Self.inclusion(rootIndex: 1))
        case .otherNullifierRoot: nonInclusionProofs.append(try Self.nonInclusion(root: Self.field(0x73)))
        case .otherNullifierRootIndex: nonInclusionProofs.append(try Self.nonInclusion(rootIndex: 1))
        case .utxoRootIndexBeyondHistory: inclusionProofs = [try Self.inclusion(rootIndex: 500)]
        case .nullifierRootIndexBeyondHistory: nonInclusionProofs = [try Self.nonInclusion(rootIndex: 100)]
        case .nonCanonicalUTXORoot: inclusionProofs = [try Self.inclusion(root: r)]
        case .nonCanonicalNullifierRoot: nonInclusionProofs = [try Self.nonInclusion(root: r)]
        case .lowElementAtNullifier: nonInclusionProofs = [try Self.nonInclusion(low: 0x50)]
        case .highElementAtNullifier: nonInclusionProofs = [try Self.nonInclusion(high: 0x50)]
        case .swappedElements: nonInclusionProofs = [try Self.nonInclusion(low: 0x60, high: 0x40)]
        }

        #expect(throws: edit.error) {
            try TransactPlan.TreeWitness(treeID: 4, inclusionProofs: inclusionProofs, nonInclusionProofs: nonInclusionProofs)
        }
    }

    private static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }

    private static func inclusion(leaf: UInt8 = 0x11, root: [UInt8] = field(0x71), rootIndex: UInt16 = 499) throws -> MerkleProof {
        try MerkleProof(leaf: field(leaf), path: Array(repeating: field(0), count: 32), leafIndex: 3, root: root, rootIndex: rootIndex)
    }

    private static func nonInclusion(nullifier: UInt8 = 0x50, low: UInt8 = 0x40, high: UInt8 = 0x60, root: [UInt8] = field(0x72),
                                     rootIndex: UInt16 = 99) throws -> NonInclusionProof {
        try NonInclusionProof(nullifier: field(nullifier), lowElement: field(low), lowElementIndex: 2, highElement: field(high),
                              path: Array(repeating: field(0), count: 40), root: root, rootIndex: rootIndex)
    }
}
