import Foundation
import Portfolio
import RPC
import Testing
@testable import widgets

/// Checks which state the portfolio section shows for each coordinator update.
struct PortfolioPresentationTests {
    /// Before the first update nothing shows; a first load without holdings shows progress.
    @Test
    func `No update shows nothing and a first load shows progress`() {
        #expect(PortfolioPresentation(nil) == .blank)
        #expect(PortfolioPresentation(Update(snapshot: nil, phase: .refreshing, revision: 1)) == .loading)
    }

    /// Holdings stay through refreshes and through failures that a new key can't fix.
    /// - Parameter phase: A refresh's progress or outcome while holdings exist.
    @Test(arguments: [
        Update.Phase.ready,
        .refreshing,
        .failed(RPCError.http(statusCode: 429, retryAfter: nil)),
        .failed(RPCError.transport(.notConnectedToInternet)),
    ])
    func `Holdings stay visible through refreshes and other failures`(phase: Update.Phase) {
        #expect(PortfolioPresentation(Update(snapshot: snapshot, phase: phase, revision: 1)) == .holdings)
    }

    /// A missing or rejected key replaces holdings, because no refresh can succeed without a new key.
    /// - Parameters:
    ///   - error: The provider's key failure.
    ///   - hasHoldings: Whether earlier holdings are available.
    @Test(arguments: [ProviderClientError.missingKey, .invalidKey], [false, true])
    func `Key failures replace holdings`(error: ProviderClientError, hasHoldings: Bool) {
        let update = Update(snapshot: hasHoldings ? snapshot : nil, phase: .failed(error), revision: 1)
        #expect(PortfolioPresentation(update) == .unavailable(PortfolioError(error)))
    }

    /// Without holdings, a failed first load shows its failure so the person can try again.
    /// - Parameters:
    ///   - error: The failed load's error.
    ///   - expected: The error the section shows.
    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: nil), PortfolioError.rateLimited),
        (.transport(.notConnectedToInternet), .unavailable),
    ])
    func `A failed first load shows its failure`(error: RPCError, expected: PortfolioError) {
        let update = Update(snapshot: nil, phase: .failed(error), revision: 1)
        #expect(PortfolioPresentation(update) == .unavailable(expected))
    }

    /// An empty wallet's complete snapshot.
    private let snapshot = Snapshot(owner: "wallet", network: .mainnet, holdings: [], fetchedAt: .distantPast)
}
