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
    func `Tree accounts hold the fee per tree`() async throws {
        let trees = UTXOTrees(rows: [IndexerResponses.match(deposits[0])], feePerTree: 108)
        let transport = StubTransport { try #require(try trees.respond(to: $0)) }

        let fee = try await ShieldedPool.treeFee(of: [0], using: SolanaRPC.devnet(transport: transport))

        #expect(fee == 108)
    }

    @Test
    func `Reads of trees without leaves are left to other replies`() async throws {
        let trees = UTXOTrees(rows: [IndexerResponses.match(deposits[0])])
        let transport = StubTransport { request in
            try trees.respond(to: request) ?? reply(to: request, payload: #""result":{"context":{"slot":7},"value":[null]}"#)
        }

        await #expect(throws: ShieldedPool.TreeError.missingTree) {
            try await ShieldedPool.treeFee(of: [5], using: SolanaRPC.devnet(transport: transport))
        }
    }

    @Test
    func `Spend rows answer reads of their transaction with a successful transact that spends their nullifiers`() async throws {
        let nullifiers = [[UInt8](repeating: 0x21, count: 32), [UInt8](repeating: 0x22, count: 32)]
        let spend = ShieldedTransaction(
            signature: IndexerResponses.signature(7), slot: 20, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [],
            nullifiers: nullifiers, isProofless: false
        )
        let trees = UTXOTrees(rows: [IndexerResponses.match(deposits[0]), IndexerResponses.row(spend)])
        let rpc = SolanaRPC.devnet(transport: StubTransport { try #require(try trees.respond(to: $0)) })

        let transaction = try #require(try await rpc.send(GetTransaction(signature: spend.signature)))
        let other = try await rpc.send(GetTransaction(signature: deposits[0].signature))

        #expect(transaction.error == nil)
        #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(nullifiers))
        #expect(other == nil)
    }

    private func statuses(in trees: UTXOTrees) async throws -> [ReceivedNote.InclusionStatus] {
        let transport = StubTransport { try #require(try trees.respond(to: $0)) }
        let notes = try deposits.flatMap { try ReceivedNote.notes(in: $0, of: sender) }
        return try await ReceivedNote.inclusionStatuses(
            of: notes, rpc: SolanaRPC.devnet(transport: transport),
            indexer: Zolana.devnet(transport: transport)
        )
    }
}
