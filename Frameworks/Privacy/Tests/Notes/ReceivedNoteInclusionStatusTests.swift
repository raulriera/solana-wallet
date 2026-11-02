import Encoding
import Foundation
import ModularArithmetic
import Testing
@testable import Privacy
@testable import RPC

struct ReceivedNoteInclusionStatusTests {
    private static let firstTree = "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor"

    private static let seventhTree = "2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7"

    @Test
    func `Each note gets its status after the proofs and then every tree's account are read`() async throws {
        let (included, includedNote) = try UTXORootHistoryTests.proofOfFifthLeaf(
            of: try PlanFixtures.utxo(lamports: 10, treeID: 0, blindingByte: 0xa1)
        )
        let (unconfirmed, unconfirmedNote) = try UTXORootHistoryTests.proofOfFifthLeaf(
            of: try PlanFixtures.utxo(lamports: 20, treeID: 7, blindingByte: 0xb2), rootIndex: 0
        )
        let (valid, refutedNote) = try UTXORootHistoryTests.proofOfFifthLeaf(
            of: try PlanFixtures.utxo(lamports: 30, treeID: 0, blindingByte: 0xc3)
        )
        let refuted = MerkleProof(leaf: valid.leaf, path: [UTXORootHistoryTests.root(1)] + valid.path.dropFirst(),
                                  leafIndex: valid.leafIndex, root: valid.root, rootIndex: valid.rootIndex)
        let proofs = [Self.firstTree: [included, refuted], Self.seventhTree: [unconfirmed]]
        let accounts = [
            UTXORootHistoryTests.account(cursor: 9, count: 10, roots: Array(repeating: UTXORootHistoryTests.root(2), count: 9) + [included.root]),
            UTXORootHistoryTests.account(cursor: 0, count: 1, roots: [UTXORootHistoryTests.root(2)]),
        ]
        let transport = Self.transport(proofs: proofs, accounts: accounts)

        let statuses = try await ReceivedNote.inclusionStatuses(
            of: [includedNote, unconfirmedNote, refutedNote], rpc: Solana(network: .devnet, transport: transport),
            indexer: Zolana(network: .devnet, transport: transport)
        )

        #expect(statuses == [.included, .unconfirmed, .refuted])
        let bodies = try await transport.requests.map(requestBody)
        #expect(bodies.map { $0["method"] as? String } == ["getMerkleProofs", "getMerkleProofs", "getMultipleAccounts"])
        let proofReads = Dictionary(uniqueKeysWithValues: try bodies.prefix(2).map { body in
            let params = try #require(body["params"] as? [String: Any])
            return (try #require(params["treeAccount"] as? String), try #require(params["leaves"] as? [String]))
        })
        #expect(proofReads == [
            Self.firstTree: [includedNote, refutedNote].map { Base58.encode($0.utxo.hash.bigEndianBytes) },
            Self.seventhTree: [Base58.encode(unconfirmedNote.utxo.hash.bigEndianBytes)],
        ])
        #expect((bodies.last?["params"] as? [Any])?.first as? [String] == [Self.firstTree, Self.seventhTree])
    }

    @Test
    func `No notes read nothing`() async throws {
        let transport = StubTransport { _ in throw CancellationError() }

        let statuses = try await ReceivedNote.inclusionStatuses(
            of: [], rpc: Solana(network: .devnet, transport: transport), indexer: Zolana(network: .devnet, transport: transport)
        )

        #expect(statuses.isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `An indexer without one proof per note fails before the trees are read`() async throws {
        let (_, note) = try UTXORootHistoryTests.proofOfFifthLeaf(of: try PlanFixtures.utxo(lamports: 10, treeID: 0))
        let transport = StubTransport { _ in throw CancellationError() }

        await #expect(throws: RPCError.invalidResponse(.mismatchedProofs)) {
            try await ReceivedNote.inclusionStatuses(of: [note], rpc: Solana(network: .devnet, transport: transport),
                                                     indexer: ProoflessIndexer())
        }
        #expect(await transport.requests.isEmpty)
    }

    private static func transport(proofs: [String: [MerkleProof]], accounts: [[UInt8]]) -> StubTransport {
        StubTransport { request in
            let body = try requestBody(request)
            guard body["method"] as? String == GetMerkleProofs.method else {
                let values = accounts.map { ShieldedPoolTreeFeeTests.account(owner: ShieldedPool.programID, data: $0) }
                return try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(values.joined(separator: ","))]}"#)
            }
            let tree = try #require((body["params"] as? [String: Any])?["treeAccount"] as? String)
            let entries = try #require(proofs[tree]).map { Self.entry(for: $0, tree: tree) }
            return try reply(to: request, payload: #""result":\#(MerkleProofReplies.result(entries))"#)
        }
    }

    private static func entry(for proof: MerkleProof, tree: String) -> String {
        MerkleProofReplies.proof(leaf: Base58.encode(proof.leaf), tree: tree, path: proof.path.map(Base58.encode),
                                 leafIndex: Int(proof.leafIndex), root: Base58.encode(proof.root),
                                 rootIndex: Int(proof.rootIndex))
    }
}

private struct ProoflessIndexer: PrivateNoteProviding {
    func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        throw CancellationError()
    }

    func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        throw CancellationError()
    }

    func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        []
    }
}
