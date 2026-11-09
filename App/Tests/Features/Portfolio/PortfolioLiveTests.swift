import Foundation
@testable import Portfolio
import RPC
import Testing
import Transactions

@Suite(.tags(.network))
struct PortfolioLiveTests {
    private let temporary = IsolatedDirectory()

    @Test(.timeLimit(.minutes(1)))
    func `Mainnet portfolio persists listed balances and shows them while reading again`() async throws {
        let transport = LiveResponses<GetMultipleAccounts>()
        let rpc = try LiveClients.client(transport: transport)
        let owner = PublicWallet.address
        let directory = temporary.url
        let store = FileSnapshotStore(directory: directory)
        let tokenListDirectory = directory.appending(path: "TokenLists")
        let key = CacheKey(owner: owner, network: .mainnet)
        let service: any PortfolioProviding = Portfolio(rpc: rpc, tokenListDirectory: tokenListDirectory,
                                                        cacheDirectory: directory)
        var updates = await service.updates(for: owner).makeAsyncIterator()

        let initial = try #require(await updates.next())
        #expect(initial.isRefreshing)
        #expect(initial.snapshot == nil)
        let completed = try #require(await updates.next())
        if let error = completed.error { throw error }
        let snapshot = try #require(completed.snapshot)
        let read = try #require(await transport.responses.first)
        let lamports = try #require(read.value.first??.lamports)
        #expect(!completed.isRefreshing)
        #expect(snapshot.owner == owner)
        #expect(snapshot.network == .mainnet)
        #expect(snapshot.holdings.map(\.symbol) == ["SOL", "USDC", "USDT"])
        #expect(snapshot.holdings.first?.amount == Amount(units: lamports, decimals: 9))
        #expect(snapshot.holdings.filter { $0.amount == nil }.map(\.symbol) == [])
        #expect(store.snapshot(for: key) == snapshot)
        #expect(await updates.next() == nil)

        let recreated: any PortfolioProviding = Portfolio(rpc: rpc, tokenListDirectory: tokenListDirectory,
                                                          cacheDirectory: directory)
        var reloaded = await recreated.updates(for: owner).makeAsyncIterator()
        let cached = try #require(await reloaded.next())
        #expect(cached.isRefreshing)
        #expect(cached.snapshot == snapshot)
        let refreshed = try #require(await reloaded.next())
        if let error = refreshed.error { throw error }
        let refreshedSnapshot = try #require(refreshed.snapshot)
        #expect(refreshedSnapshot.owner == owner)
        #expect(refreshedSnapshot.network == .mainnet)
        #expect(await reloaded.next() == nil)

        try await recreated.removeData(for: owner)
        #expect(store.snapshot(for: key) == nil)
    }
}
