import Foundation
import Testing
@testable import Privacy
@testable import RPC

struct UTXOTreesTests {
    private let sender: ShieldedAccount

    private let deposits: [ShieldedTransaction]

    init() throws {
        let vectors = try DepositNoteVectors.load().deposits
        sender = try TransferVectors.sender()
        deposits = [
            try vectors[0].transaction(signature: IndexerResponses.signature(1)),
            try vectors[1].transaction(signature: IndexerResponses.signature(2)),
        ]
    }

    @Test
    func `Held leaves are included under the roots that their trees' accounts hold`() async throws {
        let trees = UTXOTrees(rows: deposits.map(IndexerResponses.match))

        #expect(try await statuses(in: trees) == [.included, .included])
    }

    @Test
    func `Forged leaves are refuted`() async throws {
        let trees = UTXOTrees(rows: [IndexerResponses.match(deposits[0])], forging: [IndexerResponses.match(deposits[1])])

        #expect(try await statuses(in: trees) == [.included, .refuted])
    }

    @Test
    func `Leaves of trees whose roots aren't finalized are unconfirmed`() async throws {
        let trees = UTXOTrees(rows: deposits.map(IndexerResponses.match), isFinalized: false)

        #expect(try await statuses(in: trees) == [.unconfirmed, .unconfirmed])
    }

    @Test
    func `Tree accounts hold the fee per nullifier`() async throws {
        let trees = UTXOTrees(rows: [IndexerResponses.match(deposits[0])], feePerNullifier: 108)
        let transport = StubTransport { try #require(try trees.respond(to: $0)) }

        let fee = try await ShieldedPool.feePerNullifier(treeID: 0, using: Solana.devnet(transport: transport))

        #expect(fee == 108)
    }

    @Test
    func `Reads of trees without leaves are left to other replies`() async throws {
        let trees = UTXOTrees(rows: [IndexerResponses.match(deposits[0])])
        let transport = StubTransport { request in
            try trees.respond(to: request) ?? reply(to: request, payload: #""result":{"context":{"slot":7},"value":[null]}"#)
        }

        await #expect(throws: ShieldedPool.TreeError.missingTree) {
            try await ShieldedPool.feePerNullifier(treeID: 5, using: Solana.devnet(transport: transport))
        }
    }

    private func statuses(in trees: UTXOTrees) async throws -> [ReceivedNote.InclusionStatus] {
        let transport = StubTransport { try #require(try trees.respond(to: $0)) }
        let notes = try deposits.flatMap { try ReceivedNote.notes(in: $0, of: sender) }
        return try await ReceivedNote.inclusionStatuses(
            of: notes, rpc: Solana.devnet(transport: transport), indexer: Zolana(network: .devnet, transport: transport)
        )
    }
}
