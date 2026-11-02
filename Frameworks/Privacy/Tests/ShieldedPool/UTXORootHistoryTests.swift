import Foundation
import ModularArithmetic
import Testing
@testable import Privacy
@testable import RPC

struct UTXORootHistoryTests {
    enum Change: Sendable {
        case unchanged, rootOutsideHistory, rootAtAnotherSlot, rootIndexBeyondWrittenRoots
        case leafOfOtherNote, otherLeaf, otherProofIndex, otherIndexOfBoth, leafBeyondHeight, otherSibling
        case nonCanonicalSibling
    }

    @Test
    func `A proof that leads the note to the root at its slot of the history is included`() throws {
        #expect(try Self.status(after: .unchanged) == .included)
    }

    @Test(arguments: [Change.rootOutsideHistory, .rootAtAnotherSlot, .rootIndexBeyondWrittenRoots])
    func `Proofs whose root the history doesn't hold at their slot are unconfirmed`(change: Change) throws {
        #expect(try Self.status(after: change) == .unconfirmed)
    }

    @Test(arguments: [
        Change.leafOfOtherNote, .otherLeaf, .otherProofIndex, .otherIndexOfBoth, .leafBeyondHeight, .otherSibling,
        .nonCanonicalSibling,
    ])
    func `Proofs that don't lead the note to their root are refuted`(change: Change) throws {
        #expect(try Self.status(after: change) == .refuted)
    }

    @Test(arguments: [(UInt16(2), UInt16(3)), (7, 500), (499, 500)])
    func `Histories hold the written roots in slot order`(cursor: UInt16, count: UInt16) throws {
        let roots = (0..<Int(count)).map { Self.root(UInt8($0 % 251), salt: UInt8($0 / 251)) }

        let history = try UTXORootHistory(accountData: UTXOTrees.account(cursor: cursor, count: count, roots: roots))

        #expect(history.count == Int(count))
        #expect((0..<Int(count)).map { history.root(at: $0).map(Array.init) } == roots)
    }

    @Test
    func `Unwritten slots of a partial history aren't roots`() throws {
        let data = UTXOTrees.account(cursor: 1, count: 2, roots: [Self.root(1), Self.root(2), Self.root(3)])

        let history = try UTXORootHistory(accountData: data)

        #expect(history.count == 2)
        #expect((0..<3).map { history.root(at: $0).map(Array.init) } == [Self.root(1), Self.root(2), nil])
    }

    @Test(arguments: [
        (Array(UTXOTrees.account(cursor: 0, count: 1, roots: [root(1)]).dropLast()), ShieldedPool.TreeError.invalidLength),
        (UTXOTrees.account(cursor: 0, count: 1, roots: [root(1)]) + [0], .invalidLength),
        (UTXOTrees.account(cursor: 0, count: 1, capacity: 499, roots: [root(1)]), .invalidRootHistory),
        (UTXOTrees.account(cursor: 0, count: 0, roots: []), .invalidRootHistory),
        (UTXOTrees.account(cursor: 0, count: 501, roots: []), .invalidRootHistory),
        (UTXOTrees.account(cursor: 500, count: 500, roots: []), .invalidRootHistory),
        (UTXOTrees.account(cursor: 0, count: 2, roots: [root(1), root(2)]), .invalidRootHistory),
    ])
    func `Malformed tree accounts are refused`(data: [UInt8], error: ShieldedPool.TreeError) {
        #expect(throws: error) { try UTXORootHistory(accountData: data) }
    }

    static func proofOfFifthLeaf(of utxo: UTXO, rootIndex: UInt16 = 9) -> (MerkleProof, ReceivedNote) {
        let siblings = (1...32).map { Poseidon.Element(UInt64($0)) }
        var node = Poseidon.hash(siblings[0], utxo.hash)
        node = Poseidon.hash(node, siblings[1])
        node = Poseidon.hash(siblings[2], node)
        for sibling in siblings[3...] {
            node = Poseidon.hash(node, sibling)
        }
        let proof = MerkleProof(leaf: utxo.hash.bigEndianBytes, path: siblings.map(\.bigEndianBytes), leafIndex: 5,
                                root: node.bigEndianBytes, rootIndex: rootIndex)
        return (proof, ReceivedNote(utxo: utxo, leafIndex: 5, signature: "fixture", slot: 1, nullifier: .zero))
    }

    static func root(_ byte: UInt8, salt: UInt8 = 0) -> [UInt8] {
        [salt] + Array(repeating: byte, count: 31)
    }

    private static func status(after change: Change) throws -> ReceivedNote.InclusionStatus {
        let (proof, note) = try proofOfFifthLeaf(of: try PlanFixtures.utxo(lamports: 10, treeID: 0, blindingByte: 161))
        var leaf = note.utxo.hash
        var proofLeaf = proof.leaf
        var path = proof.path
        var proofIndex = proof.leafIndex
        var noteIndex = note.leafIndex
        var roots = (0..<12).map { root(UInt8($0)) }
        roots[9] = proof.root
        switch change {
        case .unchanged:
            break
        case .rootOutsideHistory:
            roots[9] = root(0x55)
        case .rootAtAnotherSlot:
            roots[9] = root(0x55)
            roots[3] = proof.root
        case .rootIndexBeyondWrittenRoots:
            roots = Array(roots.prefix(9))
            roots[0] = proof.root
        case .leafOfOtherNote:
            leaf = try PlanFixtures.utxo(lamports: 10, treeID: 0, blindingByte: 162).hash
        case .otherLeaf:
            leaf = try PlanFixtures.utxo(lamports: 10, treeID: 0, blindingByte: 162).hash
            proofLeaf = leaf.bigEndianBytes
        case .otherProofIndex:
            proofIndex += 1
        case .otherIndexOfBoth:
            proofIndex += 1
            noteIndex += 1
        case .leafBeyondHeight:
            proofIndex += 1 << 32
            noteIndex += 1 << 32
        case .otherSibling:
            path[5] = root(0x01)
        case .nonCanonicalSibling:
            path[0] = Array(repeating: 0xff, count: 32)
        }
        let history = try UTXORootHistory(accountData: UTXOTrees.account(cursor: UInt16(roots.count - 1), count: UInt16(roots.count), roots: roots))
        let changedProof = MerkleProof(leaf: proofLeaf, path: path, leafIndex: proofIndex, root: proof.root, rootIndex: proof.rootIndex)
        return history.inclusionStatus(of: leaf, at: noteIndex, provenBy: changedProof)
    }
}
