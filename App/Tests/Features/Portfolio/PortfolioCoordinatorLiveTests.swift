import Foundation
import Observation
@testable import Portfolio
import RPC
import Testing
@testable import widgets

/// Verifies independent read-only portfolio presentation against mainnet.
struct PortfolioCoordinatorLiveTests {
    /// Verifies the app observes and explicitly refreshes a public mainnet wallet.
    ///
    /// Uses real Helius subscriptions and balance reads without funding or transfers.
    /// - Throws: A provider or test prerequisite error.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func `Portfolio presentation observes and reloads a public mainnet wallet`() async throws {
        let rpc = try MainnetClients.client()
        let owner = PublicWallet.address
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = Portfolio(rpc: rpc, store: FileSnapshotStore(directory: directory),
                                tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")))
        let coordinator = PortfolioCoordinator(service: service)
        let reloaded = try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await coordinator.observe(for: owner, isActive: true) }
            defer { group.cancelAll() }
            for await update in Observations({ coordinator.update }) {
                if let error = update?.error { throw error }
                if update?.isRefreshing == false, update?.snapshot != nil { break }
            }
            let initial = try #require(coordinator.update?.snapshot)
            let initialRevision = try #require(coordinator.update?.snapshotRevision)
            #expect(initial.owner == owner)
            #expect(initial.network == .mainnet)
            #expect(initial.holdings.first?.id == .nativeSOL)

            await coordinator.refresh()
            if let error = coordinator.update?.error { throw error }
            let reloaded = try #require(coordinator.update?.snapshot)
            #expect(try #require(coordinator.update?.snapshotRevision) > initialRevision)
            #expect(reloaded.owner == owner)
            #expect(reloaded.network == .mainnet)
            return reloaded
        }
        #expect(coordinator.update?.snapshot == reloaded)
        #expect(coordinator.update?.isRefreshing == false)
    }
}
