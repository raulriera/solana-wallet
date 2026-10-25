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

    /// The amount clears once the payment sent with it succeeds, even after its review closed.
    /// - Throws: A test prerequisite error.
    @Test func `A succeeded payment clears the amount`() async throws {
        let keypad = try Keypad()
        let root = KeypadPaymentObservationRoot(portfolio: keypad.portfolio, received: keypad.received,
                                                transactions: keypad.sent.transactions)
        let hosted = try HostedWindow(root)
        defer { hosted.close() }
        try #require(try await hosted.appears())
        let model = try #require(keypad.received.payment.model)

        model.submittedRecord = keypad.sent.record
        #expect(try await keypad.sent.settle() == .succeeded)

        // The suite's time limit ends the wait if the amount never clears.
        for await quantity in Observations({ model.quantity }) where quantity == 0 { break }
        #expect(model.submittedRecord == nil)
    }

    /// A payment that succeeded while the keypad wasn't shown clears the amount when it appears, as when the tab returns.
    /// - Throws: A test prerequisite error.
    @Test func `A payment that succeeded meanwhile clears the amount when it appears`() async throws {
        let keypad = try Keypad()
        let model = try #require(keypad.received.payment.model)
        model.submittedRecord = keypad.sent.record
        #expect(try await keypad.sent.settle() == .succeeded)

        let root = KeypadPaymentObservationRoot(portfolio: keypad.portfolio, received: keypad.received,
                                                transactions: keypad.sent.transactions)
        let hosted = try HostedWindow(root)
        defer { hosted.close() }
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the amount never clears.
        for await quantity in Observations({ model.quantity }) where quantity == 0 { break }
        #expect(keypad.received.payment.model === model)
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

    /// A keypad with 1 SOL typed from a portfolio that holds SOL, and a pending payment.
    @MainActor
    private struct Keypad {
        /// The portfolio, which holds SOL.
        let portfolio = RecordingPortfolio()
        /// The keypad's payment, with 1 SOL typed.
        let received = ReceivedKeypadPayment()
        /// A payment that was sent and hasn't settled yet.
        let sent: PendingPayment

        /// Types 1 SOL with the portfolio's tokens and saves a pending payment.
        /// - Throws: A fixture error.
        init() throws {
            sent = try PendingPayment(from: UUID())
            portfolio.holdings = [KeypadPaymentObservationTests.sol]
            let tokens = try #require(portfolio.payableTokens())
            let model = PaymentModel(tokens: tokens.tokens, currencyCode: tokens.currencyCode)
            model.press(.digit(1))
            received.payment = .ready(model)
        }
    }
}
