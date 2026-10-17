import ModularArithmetic
@testable import Privacy
import RPC
import Testing

/// Verifies the checks of a declared tree's proofs and the slot and context that they give.
struct TransactPlanTreeWitnessTests {
    /// A change to valid proofs that the witness must reject.
    enum Edit: CaseIterable, CustomTestStringConvertible {
        /// No inclusion proof.
        case noInclusionProof
        /// No non-inclusion proof.
        case noNonInclusionProof
        /// A second inclusion proof under another UTXO root.
        case otherUTXORoot
        /// A second inclusion proof at another UTXO root position.
        case otherUTXORootIndex
        /// A second non-inclusion proof under another nullifier root.
        case otherNullifierRoot
        /// A second non-inclusion proof at another nullifier root position.
        case otherNullifierRootIndex
        /// A UTXO root position one past the history's 500 roots.
        case utxoRootIndexBeyondHistory
        /// A nullifier root position one past the history's 100 roots.
        case nullifierRootIndexBeyondHistory
        /// A UTXO root at r.
        case nonCanonicalUTXORoot
        /// A nullifier root at r.
        case nonCanonicalNullifierRoot
        /// A low element equal to the nullifier.
        case lowElementAtNullifier
        /// A high element equal to the nullifier.
        case highElementAtNullifier
        /// Low and high elements swapped.
        case swappedElements

        /// The rejection that the edit causes.
        var error: TransactPlan.ValidationError {
            switch self {
            case .noInclusionProof, .noNonInclusionProof, .otherUTXORoot, .otherUTXORootIndex, .otherNullifierRoot,
                 .otherNullifierRootIndex: .inconsistentProofs
            case .utxoRootIndexBeyondHistory, .nullifierRootIndexBeyondHistory: .rootIndexOutOfRange
            case .nonCanonicalUTXORoot, .nonCanonicalNullifierRoot: .invalidRoot
            case .lowElementAtNullifier, .highElementAtNullifier, .swappedElements: .invalidNonInclusionProof
            }
        }

        /// The edit's name, in test results.
        var testDescription: String { "\(self)" }
    }

    /// The BN254 scalar field's modulus r, which no canonical root reaches.
    private static let modulus = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

    /// Verifies the slot takes the tree's ID and both roots, and the context both root positions.
    ///
    /// - Throws: A validation error, which these proofs don't produce.
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

    /// Verifies that proofs that are missing, disagree, sit outside their histories, have a
    /// non-canonical root, or don't enclose their nullifier are rejected.
    ///
    /// - Parameter edit: The change to valid proofs.
    /// - Throws: A test failure if a fixture is malformed.
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

    /// A 32-byte big-endian field element of a small value.
    ///
    /// - Parameter value: The value's last byte.
    /// - Returns: Thirty-one zero bytes followed by `value`.
    private static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }

    /// An inclusion proof with a zero path.
    ///
    /// - Parameters:
    ///   - leaf: The leaf's last byte.
    ///   - root: The UTXO root.
    ///   - rootIndex: The root's position.
    /// - Returns: The proof.
    /// - Throws: A validation error for a root of another length.
    private static func inclusion(leaf: UInt8 = 0x11, root: [UInt8] = field(0x71), rootIndex: UInt16 = 499) throws -> MerkleProof {
        try MerkleProof(leaf: field(leaf), path: Array(repeating: field(0), count: 32), leafIndex: 3, root: root, rootIndex: rootIndex)
    }

    /// A non-inclusion proof with a zero path.
    ///
    /// - Parameters:
    ///   - nullifier: The nullifier's last byte.
    ///   - low: The low element's last byte.
    ///   - high: The high element's last byte.
    ///   - root: The nullifier root.
    ///   - rootIndex: The root's position.
    /// - Returns: The proof.
    /// - Throws: A validation error for a root of another length.
    private static func nonInclusion(nullifier: UInt8 = 0x50, low: UInt8 = 0x40, high: UInt8 = 0x60, root: [UInt8] = field(0x72),
                                     rootIndex: UInt16 = 99) throws -> NonInclusionProof {
        try NonInclusionProof(nullifier: field(nullifier), lowElement: field(low), lowElementIndex: 2, highElement: field(high),
                              path: Array(repeating: field(0), count: 40), root: root, rootIndex: rootIndex)
    }
}
