import Foundation
import Observation
import Portfolio
import Testing
@testable import widgets

/// Follows a portfolio in a real window, so the keypad's payment changes with the account's balances.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KeypadPaymentObservationTests {
    /// Native SOL with a balance.
    private static let sol = Holding(id: .nativeSOL, amount: Amount(units: 1_500_000_000, decimals: 9), name: nil,
                                     symbol: "SOL", imageURL: nil, valuation: nil)
    /// Native SOL after part of it was sent.
    private static let lessSOL = Holding(id: .nativeSOL, amount: Amount(units: 500_000_000, decimals: 9), name: nil,
                                         symbol: "SOL", imageURL: nil, valuation: nil)

    /// A payment starts with the portfolio's first holdings, and the same payment follows later balances.
    /// - Throws: A test prerequisite error.
    @Test func `The payment starts with the first balances and follows later ones`() async throws {
        let portfolio = RecordingPortfolio()
        let received = ReceivedKeypadPayment()
        let hosted = try HostedWindow(KeypadPaymentObservationRoot(portfolio: portfolio, received: received))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        let balances = Observations { received.payment.model?.token.balance }

        portfolio.holdings = [Self.sol]

        // The suite's time limit ends each wait if the window never reaches that state.
        for await balance in balances where balance == Decimal(string: "1.5") { break }
        let started = try #require(received.payment.model)

        portfolio.holdings = [Self.lessSOL]

        for await balance in balances where balance == Decimal(string: "0.5") { break }
        #expect(received.payment.model === started)
    }

    /// A portfolio that couldn't load any holdings leaves nothing to send.
    /// - Throws: A test prerequisite error.
    @Test func `A portfolio without holdings that failed leaves nothing to send`() async throws {
        let portfolio = RecordingPortfolio()
        let received = ReceivedKeypadPayment()
        let hosted = try HostedWindow(KeypadPaymentObservationRoot(portfolio: portfolio, received: received))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        let isLoading = Observations { received.payment.isLoading }

        portfolio.error = .invalidKey

        for await loading in isLoading where !loading { break }
        #expect(received.payment.model == nil)
    }
}
