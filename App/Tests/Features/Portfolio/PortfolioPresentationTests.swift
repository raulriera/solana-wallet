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
        Update.Phase.ready,
        .refreshing,
        .failed(RPCError.http(statusCode: 429, retryAfter: nil)),
        .failed(RPCError.transport(.notConnectedToInternet)),
    ])
    func `Holdings stay visible through refreshes and other failures`(phase: Update.Phase) {
        #expect(PortfolioPresentation(Update(snapshot: snapshot, phase: phase, revision: 1)) == .holdings)
    }

    @Test(arguments: [RPCProviderError.missingKey, .invalidKey, .unsupportedNetwork], [false, true])
    func `Provider setup failures replace holdings`(error: RPCProviderError, hasHoldings: Bool) {
        let update = Update(snapshot: hasHoldings ? snapshot : nil, phase: .failed(error), revision: 1)
        #expect(PortfolioPresentation(update) == .unavailable(PortfolioError(error)))
    }

    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: nil), PortfolioError.rateLimited),
        (.transport(.notConnectedToInternet), .unavailable),
    ])
    func `A failed first load shows its failure`(error: RPCError, expected: PortfolioError) {
        let update = Update(snapshot: nil, phase: .failed(error), revision: 1)
        #expect(PortfolioPresentation(update) == .unavailable(expected))
    }

    private let snapshot = Snapshot(owner: "wallet", network: .mainnet, holdings: [])
}
