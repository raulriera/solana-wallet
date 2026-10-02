import Foundation
@testable import Portfolio
import RPC
import Testing
import Transactions

extension SubmissionTests {
    /// Verifies live DAS retrieval, exact native SOL, persistence, and reuse by a new service.
    ///
    /// Uses the retained devnet wallet and an isolated cache without funding or transfers.
    /// - Throws: A wallet, RPC, storage, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Devnet portfolio persists DAS holdings and reuses its complete snapshot`() async throws {
        let rpc = try #require(devnetRPCs().first)
        let owner = try await DevnetWallets.address(for: DevnetWallets.senderID).value
        let observed = try await Solana(network: .devnet).send(GetMultipleAccounts(addresses: [owner]))
        let lamports = try #require(observed.value.first.flatMap { $0 }?.lamports)
        try #require(lamports > 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let key = CacheKey(owner: owner, network: .devnet)
        let service: any PortfolioProviding = Portfolio(rpc: rpc, store: store)
        var updates = await service.updates(for: owner).makeAsyncIterator()

        let initial = try #require(await updates.next())
        #expect(initial.isRefreshing)
        #expect(initial.snapshot == nil)
        let completed = try #require(await updates.next())
        if let error = completed.error { throw error }
        let snapshot = try #require(completed.snapshot)
        #expect(!completed.isRefreshing)
        #expect(snapshot.owner == owner)
        #expect(snapshot.network == .devnet)
        #expect(snapshot.holdings.first { $0.id == .nativeSOL }?.amount == Amount(units: lamports, decimals: 9))
        #expect(snapshot.holdings.first { $0.id == .nativeSOL }?.imageURL != nil)
        #expect(snapshot.holdings.allSatisfy {
            $0.id == .nativeSOL || $0.metadata?.kind == "FungibleToken" || $0.metadata?.kind == "FungibleAsset"
        })
        #expect(Set(snapshot.holdings.map(\.id)).count == snapshot.holdings.count)
        #expect(store.snapshot(for: key) == snapshot)
        #expect(await updates.next() == nil)

        let recreated: any PortfolioProviding = Portfolio(rpc: rpc, store: FileSnapshotStore(directory: directory))
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
        #expect(refreshed.snapshot?.network == .devnet)
        #expect(await reloaded.next() == nil)

        try await recreated.removeData(for: owner)
        #expect(store.snapshot(for: key) == nil)
    }
}
