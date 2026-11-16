import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct TransactPlanResolutionTests {
    enum Edit: CaseIterable, CustomTestStringConvertible {
        case missingTree
        case extraTree
        case otherTreeID
        case otherTreeAddress
        case reorderedTrees
        case nonCanonicalUTXORoot
        case nonCanonicalNullifierRoot
        case shortUTXORoot
        case utxoRootIndexBeyondHistory
        case absentUTXORootIndex
        case nullifierRootIndexBeyondHistory
        case otherUTXORoot
        case otherNullifierRoot
        case otherPublicInputHash

        var error: TransactPlan.ValidationError {
            switch self {
            case .missingTree, .extraTree: .invalidTreeContextCount
            case .otherTreeID, .otherTreeAddress, .reorderedTrees: .mismatchedTree
            case .nonCanonicalUTXORoot, .nonCanonicalNullifierRoot, .shortUTXORoot: .invalidRoot
            case .utxoRootIndexBeyondHistory, .absentUTXORootIndex, .nullifierRootIndexBeyondHistory:
                .rootIndexOutOfRange
            case .otherUTXORoot, .otherNullifierRoot, .otherPublicInputHash: .mismatchedPublicInputHash
            }
        }

        var testDescription: String { "\(self)" }
    }

    private static let modulus = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

    private static let otherRoot = Poseidon.Element(UInt64(0x99)).bigEndianBytes

    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Resolutions of the independent reference yield its tree contexts`(_ vector: ProofRequestVectors.Transact)
        throws {
        let plan = try vector.plan()
        let trees = try zip(vector.treeSlots, vector.treeContexts).map { slot, context in
            ProofResolution.Tree(
                id: slot.id, address: try ShieldedPool.tree(id: slot.id).bytes,
                utxoRoot: try fixtureBytes(slot.utxoRoot), nullifierRoot: try fixtureBytes(slot.nullifierRoot),
                utxoRootIndex: context[0], nullifierRootIndex: context[1]
            )
        }
        let resolution = ProofResolution(trees: trees, publicInputHash: try fixtureBytes(vector.publicInputHash))

        let contexts = try plan.treeContexts(from: resolution, statement: plan.publicInputs)

        #expect(contexts.map { [$0.utxoTreeRootIndex, $0.nullifierTreeRootIndex] } == vector.treeContexts)
    }

    @Test
    func `Contexts take each resolved tree's root positions in order`() throws {
        let plan = try Self.plan()

        let contexts = try plan.treeContexts(
            from: Self.resolution(of: plan, indexes: [(499, 99), (0, 0)]), statement: plan.publicInputs
        )

        #expect(contexts == [
            TreeContext(utxoTreeRootIndex: 499, nullifierTreeRootIndex: 99),
            TreeContext(utxoTreeRootIndex: 0, nullifierTreeRootIndex: 0),
        ])
    }

    @Test(arguments: Edit.allCases)
    func `Invalid resolutions are refused`(_ edit: Edit) throws {
        let plan = try Self.plan()
        let valid = try Self.resolution(of: plan)
        let r = try fixtureBytes(Self.modulus)
        var trees = valid.trees
        var hash = valid.publicInputHash
        switch edit {
        case .missingTree: trees.removeLast()
        case .extraTree: trees.append(trees[0])
        case .otherTreeID: trees[1] = Self.tree(trees[1], id: trees[1].id + 1)
        case .otherTreeAddress: trees[0] = Self.tree(trees[0], address: trees[1].address)
        case .reorderedTrees: trees.reverse()
        case .nonCanonicalUTXORoot: trees[0] = Self.tree(trees[0], utxoRoot: r)
        case .nonCanonicalNullifierRoot: trees[1] = Self.tree(trees[1], nullifierRoot: r)
        case .shortUTXORoot: trees[0] = Self.tree(trees[0], utxoRoot: Array(trees[0].utxoRoot.dropFirst()))
        case .utxoRootIndexBeyondHistory: trees[1] = Self.tree(trees[1], utxoRootIndex: 500)
        case .absentUTXORootIndex: trees[0] = Self.tree(trees[0], utxoRootIndex: .max)
        case .nullifierRootIndexBeyondHistory: trees[0] = Self.tree(trees[0], nullifierRootIndex: 100)
        case .otherUTXORoot: trees[0] = Self.tree(trees[0], utxoRoot: Self.otherRoot)
        case .otherNullifierRoot: trees[1] = Self.tree(trees[1], nullifierRoot: Self.otherRoot)
        case .otherPublicInputHash: hash[31] ^= 1
        }

        let resolution = ProofResolution(trees: trees, publicInputHash: hash)

        #expect(throws: edit.error) { try plan.treeContexts(from: resolution, statement: plan.publicInputs) }
    }

    private static func plan() throws -> TransactPlan {
        try PlanFixtures.plan(
            spending: [
                PlanFixtures.utxo(amount: 4, treeID: 3, asset: .nativeSOL),
                PlanFixtures.utxo(amount: 6, treeID: 1, blindingByte: 0xa2, asset: .nativeSOL),
            ],
            transferLamports: 7
        )
    }

    private static func resolution(of plan: TransactPlan, indexes: [(UInt16, UInt16)] = [(31, 87), (32, 88)]) throws
        -> ProofResolution {
        let trees = try zip(plan.inputTreeIDs.enumerated(), indexes).map { tree, index in
            ProofResolution.Tree(
                id: tree.element, address: try ShieldedPool.tree(id: tree.element).bytes,
                utxoRoot: Poseidon.Element(UInt64(0x71 + tree.offset)).bigEndianBytes,
                nullifierRoot: Poseidon.Element(UInt64(0x81 + tree.offset)).bigEndianBytes,
                utxoRootIndex: index.0, nullifierRootIndex: index.1
            )
        }
        return ProofResolution(trees: trees, publicInputHash: try hash(of: plan, trees: trees))
    }

    private static func hash(of plan: TransactPlan, trees: [ProofResolution.Tree]) throws -> [UInt8] {
        let slots = try trees.map { tree in
            PublicInputs.TreeSlot(
                treeID: tree.id, utxoRoot: try #require(Poseidon.Element(bigEndianBytes: tree.utxoRoot)),
                nullifierRoot: try #require(Poseidon.Element(bigEndianBytes: tree.nullifierRoot))
            )
        }
        return plan.publicInputs.hash(treeSlots: slots).bigEndianBytes
    }

    private static func tree(
        _ tree: ProofResolution.Tree,
        id: UInt16? = nil,
        address: [UInt8]? = nil,
        utxoRoot: [UInt8]? = nil,
        nullifierRoot: [UInt8]? = nil,
        utxoRootIndex: UInt16? = nil,
        nullifierRootIndex: UInt16? = nil
    ) -> ProofResolution.Tree {
        ProofResolution.Tree(
            id: id ?? tree.id, address: address ?? tree.address, utxoRoot: utxoRoot ?? tree.utxoRoot,
            nullifierRoot: nullifierRoot ?? tree.nullifierRoot, utxoRootIndex: utxoRootIndex ?? tree.utxoRootIndex,
            nullifierRootIndex: nullifierRootIndex ?? tree.nullifierRootIndex
        )
    }
}
