import Foundation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks token removal: what it removes, and what it says when the list can't be saved.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenRemovalModelTests {
    private static let bonk = Holding.Identity.asset("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263")

    /// A confirmed token leaves the wallet's list, and nothing needs explaining.
    /// - Throws: A fixture error.
    @Test
    func `Removing a token removes it from the wallet's list`() async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()

        removal.remove(Self.bonk)
        try await removal.run(in: portfolios)

        #expect(await service.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
        #expect(removal.error == nil)
        #expect(removal.attempt == nil)
    }

    /// Native SOL isn't part of the token list, so asking to remove it starts nothing.
    /// - Throws: A fixture error.
    @Test
    func `Native SOL stays`() async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()

        removal.remove(.nativeSOL)
        try await removal.run(in: portfolios)

        #expect(removal.attempt == nil)
        #expect(await service.removed.isEmpty)
    }

    /// A list that can't be read or saved keeps the token and explains why; only a failed save can be tried again.
    /// - Parameters:
    ///   - error: Why the list couldn't change.
    ///   - expected: The error the alert explains, and whether trying again can help.
    /// - Throws: A fixture error.
    @Test(arguments: [
        (TokenListError.unreadable as any Error, (error: TokenRemovalError.listUnreadable, canRetry: false)),
        (CocoaError(.fileWriteUnknown), (error: .saveFailed, canRetry: true)),
    ])
    func `A list that can't change explains why`(
        error: any Error, expected: (error: TokenRemovalError, canRetry: Bool)
    ) async throws {
        let service = PortfolioResponses()
        await service.failRemovals(with: error)
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()

        removal.remove(Self.bonk)
        try await removal.run(in: portfolios)

        #expect(removal.error == expected.error)
        #expect(removal.error?.canRetry == expected.canRetry)
        #expect(removal.attempt == nil)
    }

    /// Trying a failed save again removes the same token.
    /// - Throws: A fixture error.
    @Test
    func `Trying a failed save again removes the same token`() async throws {
        let service = PortfolioResponses()
        await service.failRemovals(with: CocoaError(.fileWriteUnknown))
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()
        removal.remove(Self.bonk)
        try await removal.run(in: portfolios)

        await service.failRemovals(with: nil)
        removal.retry()
        try await removal.run(in: portfolios)

        #expect(await service.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
        #expect(removal.attempt == nil)
    }

    /// The save can't stop partway, so an error during a cancelled task is still explained.
    /// - Throws: A fixture error.
    @Test
    func `A cancelled removal still explains a failed save`() async throws {
        let service = PortfolioResponses()
        await service.failRemovals(with: CocoaError(.fileWriteUnknown))
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()
        removal.remove(Self.bonk)
        let attempt = removal.attempt

        let account = try Account.fixture(index: 1)
        let run = Task { await removal.run(attempt, in: portfolios, for: account, on: .devnet) }
        run.cancel()
        await run.value

        #expect(removal.error == .saveFailed)
    }

    /// The scene's task can start again with the same attempt while the save runs, as after a tab switch;
    /// the token is removed once.
    /// - Throws: A fixture error.
    @Test
    func `An attempt removes its token once`() async throws {
        let gate = Suspension()
        let service = PortfolioResponses(removalGate: gate)
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()
        removal.remove(Self.bonk)
        let attempt = removal.attempt
        let account = try Account.fixture(index: 1)
        let first = Task { await removal.run(attempt, in: portfolios, for: account, on: .devnet) }
        await gate.waitUntilStarted()

        await removal.run(attempt, in: portfolios, for: account, on: .devnet)
        gate.resume()
        await first.value

        #expect(await service.removed.count == 1)
    }
}

private extension TokenRemovalModel {
    /// Removes the requested token from the test account's list on devnet, as the portfolio's task does.
    /// - Parameter portfolios: The portfolios under test.
    /// - Throws: A fixture error.
    func run(in portfolios: PortfolioStore) async throws {
        await run(attempt, in: portfolios, for: try .fixture(index: 1), on: .devnet)
    }
}
