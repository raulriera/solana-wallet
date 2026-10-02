import Foundation
import Observation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

extension SubmissionTests {
    /// Verifies the app observes and explicitly refreshes the retained devnet wallet.
    ///
    /// Uses real Helius subscriptions and DAS without funding or transfers.
    /// - Throws: A wallet, provider, or test prerequisite error.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func `Portfolio presentation observes and reloads the retained devnet wallet`() async throws {
        let rpc = try #require(devnetRPCs().first)
        let owner = try await DevnetWallets.address(for: DevnetWallets.senderID).value
        let coordinator = PortfolioCoordinator(service: Portfolio(rpc: rpc))
        let openedAt = Date()
        let viewing = Task { await coordinator.observe(for: owner, isActive: true) }
        defer { viewing.cancel() }
        for await update in Observations({ coordinator.update }) {
            if let error = update?.error { throw error }
            if update?.isRefreshing == false, let snapshot = update?.snapshot,
               snapshot.fetchedAt >= openedAt { break }
        }
        let initial = try #require(coordinator.update?.snapshot)
        #expect(initial.owner == owner)
        #expect(initial.network == .devnet)
        #expect(initial.holdings.first { $0.id == .nativeSOL }?.imageURL != nil)

        await coordinator.refresh()
        if let error = coordinator.update?.error { throw error }
        let reloaded = try #require(coordinator.update?.snapshot)
        #expect(reloaded.fetchedAt > initial.fetchedAt)
        #expect(reloaded.owner == owner)
        #expect(reloaded.network == .devnet)
        viewing.cancel()
        await viewing.value
        #expect(coordinator.update?.snapshot == reloaded)
        #expect(coordinator.update?.isRefreshing == false)
    }
}
