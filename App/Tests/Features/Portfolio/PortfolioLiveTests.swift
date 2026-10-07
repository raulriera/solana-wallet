import Foundation
@testable import Portfolio
import RPC
import Testing
import Transactions

/// Verifies read-only mainnet balance reads and caching with a public wallet fixture.
struct PortfolioLiveTests {
    /// Verifies a live balance read of the default token list, exact native SOL, persistence, and reuse by a new service.
    ///
    /// Uses a public address and isolated storage without wallet recovery or funding.
    /// - Throws: An RPC, storage, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Mainnet portfolio persists listed balances and reuses its complete snapshot`() async throws {
        let transport = LiveResponses<GetMultipleAccounts>()
        let rpc = try MainnetClients.client(transport: transport)
        let owner = PublicWallet.address
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let tokenLists = FileTokenListStore(directory: directory.appendingPathComponent("TokenLists"))
        let key = CacheKey(owner: owner, network: .mainnet)
        let service: any PortfolioProviding = Portfolio(rpc: rpc, store: store, tokenLists: tokenLists)
        var updates = await service.updates(for: owner).makeAsyncIterator()

        let initial = try #require(await updates.next())
        #expect(initial.isRefreshing)
        #expect(initial.snapshot == nil)
        let completed = try #require(await updates.next())
        if let error = completed.error { throw error }
        let snapshot = try #require(completed.snapshot)
        let read = try #require(await transport.responses.first)
        #expect(!completed.isRefreshing)
        #expect(snapshot.owner == owner)
        #expect(snapshot.network == .mainnet)
        #expect(snapshot.holdings.map(\.symbol) == ["SOL", "USDC", "USDT"])
        // A wallet without an account on the ledger holds no SOL.
        #expect(snapshot.holdings.first?.amount == Amount(units: read.value.first??.lamports ?? 0, decimals: 9))
        #expect(snapshot.holdings.allSatisfy { $0.amount != nil })
        #expect(store.snapshot(for: key) == snapshot)
        #expect(await updates.next() == nil)

        let recreated: any PortfolioProviding = Portfolio(rpc: rpc, store: FileSnapshotStore(directory: directory),
                                                          tokenLists: tokenLists)
        var reused = await recreated.updates(for: owner).makeAsyncIterator()
        let cached = try #require(await reused.next())
        #expect(!cached.isRefreshing)
        #expect(cached.snapshot == snapshot)
        #expect(await reused.next() == nil)

        var reloaded = await recreated.updates(for: owner, policy: .reload).makeAsyncIterator()
        #expect(try #require(await reloaded.next()).isRefreshing)
        let refreshed = try #require(await reloaded.next())
        if let error = refreshed.error { throw error }
        #expect(refreshed.snapshot?.owner == owner)
        #expect(refreshed.snapshot?.network == .mainnet)
        #expect(await reloaded.next() == nil)

        try await recreated.removeData(for: owner)
        #expect(store.snapshot(for: key) == nil)
    }
}
