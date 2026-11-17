import Foundation
import Testing
import Transactions
import Wallet
@testable import RPC
@testable import widgets

struct RedeemCodeScanTests {
    @Test
    func `Batches hold consecutive indices below the hardened range`() {
        let limit: UInt32 = 1 << 31

        #expect(RedeemCodeScan.candidates(from: 3, count: 4) == [3, 4, 5, 6])
        #expect(RedeemCodeScan.candidates(from: 0, count: 1) == [0])
        #expect(RedeemCodeScan.candidates(from: limit - 2, count: 20) == [limit - 2, limit - 1])
        #expect(RedeemCodeScan.candidates(from: limit, count: 20).isEmpty)
    }

    @Test(arguments: [([], 2), ([2, 5], 8), ([8], nil)] as [(Set<UInt32>, UInt32?)])
    func `The choice follows the highest used index`(used: Set<UInt32>, choice: UInt32?) {
        #expect(RedeemCodeScan.choice(in: [2, 3, 5, 8], used: used) == choice)
    }

    @Test
    func `Fundings name each paid index and its first transaction`() async throws {
        let keys = try await Self.keys()
        let responses = HTTPResponses.privateNotes(deposits: [
            try RedeemCodeFixtures.deposit(1, to: keys.oneTimeAccount(at: 4), leafIndex: 2),
            try RedeemCodeFixtures.deposit(1, to: keys.oneTimeAccount(at: 6), leafIndex: 3),
            try RedeemCodeFixtures.deposit(1, to: keys.oneTimeAccount(at: 4), leafIndex: 5),
        ])

        let fundings = try await RedeemCodeScan.fundings(of: [3, 4, 6], from: keys, using: await Self.client(responses))

        #expect(fundings.map(\.index) == [4, 6])
        #expect(fundings.map(\.signature) == [RedeemCodeFixtures.signature(ofDepositAt: 2),
                                              RedeemCodeFixtures.signature(ofDepositAt: 3)])
        #expect(fundings.map(\.address.value) == [try keys.oneTimeAccount(at: 4).address,
                                                  try keys.oneTimeAccount(at: 6).address])
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses) == [3])
    }

    @Test
    func `Fundings after the first read are found`() async throws {
        let keys = try await Self.keys()
        let early = try keys.oneTimeAccount(at: 3)
        let late = try keys.oneTimeAccount(at: 4)
        let firstRead = try (2..<10).map { try RedeemCodeFixtures.deposit(1, to: early, leafIndex: $0) }
        let responses = HTTPResponses.privateNotes(
            deposits: firstRead + [try RedeemCodeFixtures.deposit(1, to: late, leafIndex: 10)], depositsPerPage: 1
        )

        let fundings = try await RedeemCodeScan.fundings(of: [3, 4], from: keys, using: await Self.client(responses))

        #expect(fundings.map(\.index) == [3, 4])
        #expect(fundings.map(\.signature) == [RedeemCodeFixtures.signature(ofDepositAt: 2),
                                              RedeemCodeFixtures.signature(ofDepositAt: 10)])
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses) == [2, 2])
    }

    @Test
    func `Fundings that don't end within 128 reads fail`() async throws {
        let keys = try await Self.keys()
        let row = try RedeemCodeFixtures.deposit(1, to: keys.oneTimeAccount(at: 3), leafIndex: 2)
        let transactions = [IndexerReplies.page([], in: "events")]
        let responses = HTTPResponses([GetShieldedTransactionsByTags.method: transactions]) { request in
            let page = try PageCursor.page(of: request)
            return IndexerReplies.page([row], in: "outputs", next: PageCursor.cursor(forPage: page + 1))
        }
        let client = await Self.client(responses)

        await #expect(throws: RPCError.invalidResponse(.endlessStream)) {
            try await RedeemCodeScan.fundings(of: [3], from: keys, using: client)
        }
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses).count == 128)
    }

    @Test
    func `A discovery batch reads 500 tags at once across a gap`() async throws {
        let keys = try await Self.keys()
        let responses = HTTPResponses.privateNotes(deposits: [
            try RedeemCodeFixtures.deposit(1, to: keys.oneTimeAccount(at: 0), leafIndex: 2),
            try RedeemCodeFixtures.deposit(1, to: keys.oneTimeAccount(at: 499), leafIndex: 3),
        ])
        let batch = RedeemCodeScan.candidates(from: 0, count: RedeemCodeScan.discoveryBatchSize)

        let fundings = try await RedeemCodeScan.fundings(of: batch, from: keys, using: await Self.client(responses))

        #expect(fundings.map(\.index) == [0, 499])
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses) == [500])
    }

    @Test
    func `Statuses come from the indexer`() async throws {
        let keys = try await Self.keys()
        let held = try keys.oneTimeAccount(at: 1)
        let swept = try keys.oneTimeAccount(at: 2)
        let responses = HTTPResponses.privateNotes(
            deposits: [try RedeemCodeFixtures.deposit(700, to: held, leafIndex: 3),
                       try RedeemCodeFixtures.deposit(500, to: swept, leafIndex: 4)],
            spends: [try RedeemCodeFixtures.spend(of: 500, to: swept, leafIndex: 4)]
        )

        let client = await Self.client(responses)

        let statuses = try await RedeemCodeScan.statuses(of: [1, 2, 3], from: keys, rpc: client, indexer: client)

        #expect(statuses == [1: .unspent(lamports: 700, signature: RedeemCodeFixtures.signature(ofDepositAt: 3)),
                             2: .spent, 3: .unfunded])
    }

    @Test
    func `Codes whose notes aren't confirmed are unconfirmed until a later scan confirms them`() async throws {
        let keys = try await Self.keys()
        let deposit = try RedeemCodeFixtures.deposit(700, to: keys.oneTimeAccount(at: 1), leafIndex: 3)
        async let laggingClient = Self.client(HTTPResponses.privateNotes(
            deposits: [deposit], trees: UTXOTrees(rows: [deposit], isFinalized: false)
        ))
        async let finalizedClient = Self.client(HTTPResponses.privateNotes(deposits: [deposit]))
        let (lagging, finalized) = await (laggingClient, finalizedClient)

        let unconfirmed = try await RedeemCodeScan.statuses(of: [1, 2], from: keys, rpc: lagging, indexer: lagging)
        let confirmed = try await RedeemCodeScan.statuses(of: [1, 2], from: keys, rpc: finalized, indexer: finalized)

        #expect(unconfirmed == [1: .unconfirmed, 2: .unfunded])
        #expect(confirmed == [1: .unspent(lamports: 700, signature: RedeemCodeFixtures.signature(ofDepositAt: 3)), 2: .unfunded])
    }

    private static func keys() async throws -> PrivateBalanceKeyRecord {
        try await PrivateBalanceFixtures.keys(for: PrivateBalanceFixtures.account())
    }

    @MainActor
    private static func client(_ responses: HTTPResponses) -> SelectedRPCProvider {
        responses.rpcProvider(network: .devnet, rpcStore: .inMemory(selection: .helius, key: "fixture-key"))
    }
}
