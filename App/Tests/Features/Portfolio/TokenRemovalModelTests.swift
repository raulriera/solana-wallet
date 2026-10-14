import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

/// Checks token removal: what it removes, and what it says when the list can't be saved.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenRemovalModelTests {
    private static let bonk = Holding.Identity.asset("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263")

    /// A confirmed token leaves the wallet's list, and nothing needs explaining.
    @Test
    func `Removing a token removes it from the wallet's list`() async {
        let portfolio = RecordingPortfolio()
        let removal = TokenRemovalModel(coordinator: portfolio)

        removal.remove(Self.bonk)
        await removal.run(removal.attempt)

        #expect(portfolio.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
        #expect(removal.error == nil)
        #expect(removal.attempt == nil)
    }

    /// Native SOL isn't part of the token list, so asking to remove it starts nothing.
    @Test
    func `Native SOL stays`() async {
        let portfolio = RecordingPortfolio()
        let removal = TokenRemovalModel(coordinator: portfolio)

        removal.remove(.nativeSOL)
        await removal.run(removal.attempt)

        #expect(removal.attempt == nil)
        #expect(portfolio.removed.isEmpty)
    }

    /// A list that can't be read or saved keeps the token and explains why.
    /// - Parameters:
    ///   - error: Why the list couldn't change.
    ///   - expected: The error the alert explains.
    @Test(arguments: [
        (TokenListError.unreadable as any Error, TokenRemovalError.listUnreadable),
        (CocoaError(.fileWriteUnknown), .saveFailed),
    ])
    func `A list that can't change explains why`(error: any Error, expected: TokenRemovalError) async {
        let portfolio = RecordingPortfolio()
        portfolio.removeError = error
        let removal = TokenRemovalModel(coordinator: portfolio)

        removal.remove(Self.bonk)
        await removal.run(removal.attempt)

        #expect(removal.error == expected)
        #expect(removal.attempt == nil)
    }

    /// The save can't stop partway, so an error during a cancelled task is still explained.
    @Test
    func `A cancelled removal still explains a failed save`() async {
        let portfolio = RecordingPortfolio()
        portfolio.removeError = CocoaError(.fileWriteUnknown)
        let removal = TokenRemovalModel(coordinator: portfolio)
        removal.remove(Self.bonk)
        let attempt = removal.attempt

        let run = Task { await removal.run(attempt) }
        run.cancel()
        await run.value

        #expect(removal.error == .saveFailed)
    }

    /// The scene's task can start again with the same attempt while the save runs, as after a tab switch;
    /// the token is removed once.
    @Test
    func `An attempt removes its token once`() async {
        let portfolio = RecordingPortfolio()
        portfolio.holdsRemovals = true
        let removal = TokenRemovalModel(coordinator: portfolio)
        removal.remove(Self.bonk)
        let attempt = removal.attempt
        let first = Task { await removal.run(attempt) }
        for await _ in portfolio.heldRemovals { break }

        await removal.run(attempt)
        portfolio.releaseRemovals()
        await first.value

        #expect(portfolio.removed.count == 1)
    }
}
