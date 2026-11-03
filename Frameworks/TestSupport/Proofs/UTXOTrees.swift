import Encoding
import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct UTXOTrees: Sendable {
    private struct Output {
        let hash: String
        let treeID: UInt16
        let leafIndex: UInt64
    }

    private struct Tree {
        let address: String
        let levels: [[UInt64: Poseidon.Element]]
        let indices: [String: UInt64]

        var root: Poseidon.Element {
            levels[UTXOTrees.height][0] ?? UTXOTrees.zeros[UTXOTrees.height]
        }

        init(address: String, leaves: [UInt64: Poseidon.Element], indices: [String: UInt64]) {
            var levels = [leaves]
            for level in 0..<UTXOTrees.height {
                let nodes = levels[level]
                let parents = Set(nodes.keys.map { $0 >> 1 }).map { parent in
                    let zero = UTXOTrees.zeros[level]
                    return (parent, Poseidon.hash(nodes[parent << 1] ?? zero, nodes[parent << 1 | 1] ?? zero))
                }
                levels.append(Dictionary(uniqueKeysWithValues: parents))
            }
            self.address = address
            self.levels = levels
            self.indices = indices
        }

        func proof(of leaf: String, rootIndex: Int) throws -> String {
            let index = try #require(indices[leaf], "Unexpected leaf \(leaf)")
            let path = (0..<UTXOTrees.height).map { level in
                levels[level][(index >> level) ^ 1] ?? UTXOTrees.zeros[level]
            }
            return MerkleProofReplies.proof(
                leaf: leaf, tree: address, path: path.map { Base58.encode($0.bigEndianBytes) }, leafIndex: Int(index),
                root: Base58.encode(root.bigEndianBytes), rootIndex: rootIndex
            )
        }
    }

    private static let height = 32

    private static let zeros = Array(sequence(first: Poseidon.Element.zero) { Poseidon.hash($0, $0) }.prefix(height + 1))

    private let rows: [String]
    private let forgedRows: [String]
    private let isFinalized: Bool
    private let feePerNullifier: UInt64

    init(rows: [String], forging forgedRows: [String] = [], isFinalized: Bool = true, feePerNullifier: UInt64 = 0) {
        self.rows = rows
        self.forgedRows = forgedRows
        self.isFinalized = isFinalized
        self.feePerNullifier = feePerNullifier
    }

    static func account(cursor: UInt16, count: UInt16, capacity: UInt16 = 500, roots: [[UInt8]],
                        feePerNullifier: UInt64 = 0) -> [UInt8] {
        var data = [1] + [UInt8](repeating: 0, count: 7)
        data.appendLittleEndian(feePerNullifier)
        data += [UInt8](repeating: 0, count: 96)
        data.appendLittleEndian(cursor)
        data.appendLittleEndian(count)
        data.appendLittleEndian(capacity)
        data += [UInt8](repeating: 0, count: 1_152 - data.count) + roots.joined()
        return data + [UInt8](repeating: 0, count: 40_080 - data.count)
    }

    func respond(to request: URLRequest) throws -> (Data, URLResponse)? {
        guard let data = request.httpBody, let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        switch body["method"] as? String {
        case GetMerkleProofs.method?:
            let requested = try MerkleProofReplies.requestedLeaves(in: request)
            guard let tree = try trees()[requested.tree] else { return nil }
            let proofs = try requested.leaves.map { try tree.proof(of: $0, rootIndex: 1) }
            return try reply(to: request, payload: #""result":\#(MerkleProofReplies.result(proofs))"#)
        case GetMultipleAccounts.method?:
            let addresses = try #require((body["params"] as? [Any])?.first as? [String])
            let trees = try trees()
            let read = addresses.compactMap { trees[$0] }
            guard !read.isEmpty, read.count == addresses.count else { return nil }
            return try reply(to: request, payload: #""result":\#(AccountReplies.accounts(read.map(account(of:))))"#)
        case GetTransaction.method?:
            let signature = try #require((body["params"] as? [Any])?.first as? String)
            let nullifiers = try rows.compactMap(Self.spend(in:)).first { $0.signature == signature }?.nullifiers
            return try reply(to: request, payload: #""result":\#(nullifiers.map { SpendTransactions.result(spending: $0) } ?? "null")"#)
        default:
            return nil
        }
    }

    private func trees() throws -> [String: Tree] {
        var leaves: [UInt16: [UInt64: Poseidon.Element]] = [:]
        var indices: [UInt16: [String: UInt64]] = [:]
        for output in try rows.flatMap(Self.outputs(in:)) {
            let bytes = try #require(Base58.decode(output.hash, byteCount: 32))
            let hash = try #require(Poseidon.Element(bigEndianBytes: bytes))
            let held = leaves[output.treeID]?[output.leafIndex]
            try #require(held == nil || held == hash, "Two leaves at index \(output.leafIndex) of tree \(output.treeID)")
            if output.leafIndex >> Self.height == 0 { leaves[output.treeID, default: [:]][output.leafIndex] = hash }
            indices[output.treeID, default: [:]][output.hash] = output.leafIndex
        }
        for output in try forgedRows.flatMap(Self.outputs(in:)) {
            indices[output.treeID, default: [:]][output.hash] = output.leafIndex
        }
        return Dictionary(uniqueKeysWithValues: try indices.map { treeID, indices in
            let address = try ShieldedPool.tree(id: treeID).value
            return (address, Tree(address: address, leaves: leaves[treeID] ?? [:], indices: indices))
        })
    }

    private func account(of tree: Tree) -> String {
        let roots = [Self.zeros[Self.height]] + (isFinalized ? [tree.root] : [])
        let data = Self.account(cursor: UInt16(roots.count - 1), count: UInt16(roots.count), roots: roots.map(\.bigEndianBytes),
                                feePerNullifier: feePerNullifier)
        return AccountReplies.account(owner: ShieldedPool.programID, data: data)
    }

    private static func spend(in row: String) throws -> (signature: String, nullifiers: [[UInt8]])? {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any])
        guard let signature = object["txSignature"] as? String, let nullifiers = object["nullifiers"] as? [String],
              !nullifiers.isEmpty else { return nil }
        return (signature, try nullifiers.map { try #require(Base58.decode($0, byteCount: 32)) })
    }

    private static func outputs(in row: String) throws -> [Output] {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any])
        let slots = (object["outputSlots"] as? [[String: Any]] ?? []) + [object["outputSlot"] as? [String: Any]].compactMap(\.self)
        return try slots.map { slot in
            let context = try #require(slot["outputContext"] as? [String: Any])
            return Output(
                hash: try #require(context["hash"] as? String),
                treeID: try #require((context["treeId"] as? Int).flatMap(UInt16.init(exactly:))),
                leafIndex: try #require((context["leafIndex"] as? Int).flatMap(UInt64.init(exactly:)))
            )
        }
    }
}
