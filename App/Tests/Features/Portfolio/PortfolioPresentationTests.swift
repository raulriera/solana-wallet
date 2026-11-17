import Foundation
import Portfolio
import RPC
import Testing
@testable import widgets

struct PortfolioPresentationTests {
    @Test
    func `No update shows nothing and a first load shows progress`() {
        #expect(PortfolioPresentation(nil) == .blank)
        #expect(PortfolioPresentation(Update(snapshot: nil, phase: .refreshing, revision: 1)) == .loading)
    }

    @Test(arguments: [
        Update.Phase.refreshing,
        .failed(RPCError.http(statusCode: 429, retryAfter: nil)),
    ])
    func `Holdings stay visible through refreshes and other failures`(phase: Update.Phase) {
        #expect(PortfolioPresentation(Update(snapshot: snapshot, phase: phase, revision: 1)) == .holdings)
    }

    @Test(arguments: [false, true])
    func `Provider setup failures replace holdings`(hasHoldings: Bool) {
        let error = RPCProviderError.missingKey
        let update = Update(snapshot: hasHoldings ? snapshot : nil, phase: .failed(error), revision: 1)
        #expect(PortfolioPresentation(update) == .unavailable(PortfolioError(error)))
    }

    @Test
    func `A failed first load shows its failure`() {
        let update = Update(snapshot: nil, phase: .failed(RPCError.http(statusCode: 429, retryAfter: nil)), revision: 1)
        #expect(PortfolioPresentation(update) == .unavailable(.rateLimited))
    }

    private let snapshot = Snapshot(owner: "wallet", network: .mainnet, holdings: [])
}
