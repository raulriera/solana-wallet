import Foundation
@testable import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@Suite(.tags(.network))
struct PortfolioLiveTests {
    private let temporary = IsolatedDirectory()

    @Test(.timeLimit(.minutes(1)))
    func `Mainnet portfolio saves its read and shows it while reading again`() async throws {
        let rpc = try LiveClients.client()
        let owner = try await DevnetWallets.configured().sender.address.value
        let directory = temporary.url
        let store = FileSnapshotStore(directory: directory)
        let tokenListDirectory = directory.appending(path: "TokenLists")
        let key = CacheKey(owner: owner, network: .mainnet)
        let service: any PortfolioProviding = Portfolio(rpc: rpc, tokenListDirectory: tokenListDirectory,
                                                        cacheDirectory: directory)
        var updates = await service.updates(for: owner).makeAsyncIterator()

        _ = try #require(await updates.next())
        let completed = try #require(await updates.next())
        if let error = completed.error { throw error }
        let snapshot = try #require(completed.snapshot)
        #expect(store.snapshot(for: key) == snapshot)
        #expect(await updates.next() == nil)

        let recreated: any PortfolioProviding = Portfolio(rpc: rpc, tokenListDirectory: tokenListDirectory,
                                                          cacheDirectory: directory)
        var reloaded = await recreated.updates(for: owner).makeAsyncIterator()
        let cached = try #require(await reloaded.next())
        #expect(cached.snapshot == snapshot)
        let refreshed = try #require(await reloaded.next())
        if let error = refreshed.error { throw error }
        #expect(await reloaded.next() == nil)

        try await recreated.removeData(for: owner)
        #expect(store.snapshot(for: key) == nil)
    }
}
