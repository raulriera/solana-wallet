import Foundation
import Observation
import RPC
import Testing
import Transactions
@testable import Portfolio
@testable import widgets

@Suite(.tags(.network))
struct PortfolioStoreLiveTests {
    private let temporary = IsolatedDirectory()

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func `The shared portfolios observe and reload a public mainnet wallet`() async throws {
        let rpc = try LiveClients.client()
        let account = try Account.publicWallet()
        let owner = account.address.value
        let directory = temporary.url
        let service = Portfolio(rpc: rpc, tokenListDirectory: directory.appending(path: "TokenLists"),
                                cacheDirectory: directory)
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
        let portfolio = try #require(portfolios.portfolio(for: account, on: .mainnet))
        let update = try #require(portfolio.update)
        #expect(update.snapshot == reloaded)
        #expect(!update.isRefreshing)
    }
}
