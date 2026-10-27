import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks that the token removal action asks the portfolio's removals to remove the token it's given.
@MainActor
struct TokenRemovalActionTests {
    /// Removing a token starts a removal of that token.
    /// - Throws: A fixture error.
    @Test func `Removing a token starts its removal`() async throws {
        let service = PortfolioResponses()
        let removal = TokenRemovalModel()
        let removeToken = TokenRemovalAction(removal: removal)

        removeToken(.asset("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"))
        #expect(removal.attempt != nil)

        await removal.run(removal.attempt, in: .serving(service), for: try .fixture(index: 1), on: .devnet)
        #expect(await service.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
    }

    /// Native SOL isn't part of the token list, so removing it starts nothing.
    @Test func `Removing native SOL starts nothing`() {
        let removal = TokenRemovalModel()
        let removeToken = TokenRemovalAction(removal: removal)

        removeToken(.nativeSOL)
        #expect(removal.attempt == nil)
    }
}
