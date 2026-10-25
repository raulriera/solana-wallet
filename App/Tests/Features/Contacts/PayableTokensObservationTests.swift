import Foundation
import Observation
import Portfolio
import Testing
@testable import widgets

/// Follows a portfolio in a real window, so the keypad's tokens change with the account's balances.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PayableTokensObservationTests {
    /// Native SOL with a balance.
    private static let sol = Holding(id: .nativeSOL, amount: Amount(units: 1_500_000_000, decimals: 9), name: nil,
                                     symbol: "SOL", imageURL: nil, valuation: nil)
    /// Native SOL after part of it was sent.
    private static let lessSOL = Holding(id: .nativeSOL, amount: Amount(units: 500_000_000, decimals: 9), name: nil,
                                         symbol: "SOL", imageURL: nil, valuation: nil)

    /// Tokens arrive with the portfolio's first holdings and follow later balances.
    /// - Throws: A test prerequisite error.
    @Test func `Tokens follow the portfolio's balances`() async throws {
        let portfolio = RecordingPortfolio()
        let received = ReceivedPayableTokens()
        let hosted = try HostedWindow(PayableTokensObservationRoot(portfolio: portfolio, received: received))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        let balances = Observations { received.tokens?.tokens.first?.balance }

        portfolio.holdings = [Self.sol]

        // The suite's time limit ends each wait if the window never reaches that state.
        for await balance in balances where balance == Decimal(string: "1.5") { break }

        portfolio.holdings = [Self.lessSOL]

        for await balance in balances where balance == Decimal(string: "0.5") { break }
    }
}
