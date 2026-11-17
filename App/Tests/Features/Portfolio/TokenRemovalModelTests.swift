import Foundation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenRemovalModelTests {
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

    @Test
    func `Removing a token removes it from the wallet's list`() async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()

        removal.remove(try Address(Self.bonk))
        try await removal.run(in: portfolios)

        #expect(await service.removed.map(\.value) == [Self.bonk])
        #expect(removal.error == nil)
        #expect(removal.attempt == nil)
    }

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

        removal.remove(try Address(Self.bonk))
        try await removal.run(in: portfolios)

        #expect(removal.error == expected.error)
        #expect(removal.error?.canRetry == expected.canRetry)
        #expect(removal.attempt == nil)
    }

    @Test
    func `Trying a failed save again removes the same token`() async throws {
        let service = PortfolioResponses()
        await service.failRemovals(with: CocoaError(.fileWriteUnknown))
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()
        removal.remove(try Address(Self.bonk))
        try await removal.run(in: portfolios)

        await service.failRemovals(with: nil)
        removal.retry()
        try await removal.run(in: portfolios)

        #expect(await service.removed.map(\.value) == [Self.bonk])
        #expect(removal.attempt == nil)
    }

    @Test
    func `An attempt removes its token once`() async throws {
        let gate = Suspension()
        let service = PortfolioResponses(removalGate: gate)
        let portfolios = PortfolioStore.serving(service)
        let removal = TokenRemovalModel()
        removal.remove(try Address(Self.bonk))
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
    func run(in portfolios: PortfolioStore) async throws {
        await run(attempt, in: portfolios, for: try .fixture(index: 1), on: .devnet)
    }
}
