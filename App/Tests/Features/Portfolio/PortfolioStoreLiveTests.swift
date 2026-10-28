import Foundation
import Observation
import RPC
import Testing
import Transactions
@testable import Portfolio
@testable import widgets

/// Verifies the shared portfolios against mainnet, read-only.
@Suite(.tags(.network))
struct PortfolioStoreLiveTests {
    /// Verifies the app observes and explicitly refreshes a public mainnet wallet through the shared portfolios.
    ///
    /// Uses real Helius subscriptions and balance reads without funding or transfers.
    /// - Throws: A provider or test prerequisite error.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func `The shared portfolios observe and reload a public mainnet wallet`() async throws {
        let rpc = try LiveClients.client()
        let account = try Account.publicWallet()
        let owner = account.address.value
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = Portfolio(rpc: rpc, store: FileSnapshotStore(directory: directory),
                                tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")))
        let portfolios = PortfolioStore.serving(service)
        let reloaded = try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await portfolios.observe(account, on: .mainnet) }
            defer { group.cancelAll() }
            for await update in Observations({ portfolios.portfolio(for: account, on: .mainnet)?.update }) {
                if let error = update?.error { throw error }
                if update?.isRefreshing == false, update?.snapshot != nil { break }
            }
            let portfolio = try #require(portfolios.portfolio(for: account, on: .mainnet))
            let initial = try #require(portfolio.update?.snapshot)
            let initialRevision = try #require(portfolio.update?.snapshotRevision)
            #expect(initial.owner == owner)
            #expect(initial.network == .mainnet)
            #expect(initial.holdings.first?.id == .nativeSOL)

            await portfolios.refresh(account, on: .mainnet)
            if let error = portfolio.update?.error { throw error }
            let reloaded = try #require(portfolio.update?.snapshot)
            #expect(try #require(portfolio.update?.snapshotRevision) > initialRevision)
            #expect(reloaded.owner == owner)
            #expect(reloaded.network == .mainnet)
            return reloaded
        }
        let portfolio = portfolios.portfolio(for: account, on: .mainnet)
        #expect(portfolio?.update?.snapshot == reloaded)
        #expect(portfolio?.update?.isRefreshing == false)
    }
}
