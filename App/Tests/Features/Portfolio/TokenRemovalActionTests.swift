import Portfolio
import Testing
import Transactions
@testable import widgets

/// Checks that the token removal action asks the window's removals to remove the token it's given.
@MainActor
struct TokenRemovalActionTests {
    /// Removing a token starts a removal of that token.
    @Test func `Removing a token starts its removal`() async {
        let portfolio = RecordingPortfolio()
        let removal = TokenRemovalModel(coordinator: portfolio)
        let removeToken = TokenRemovalAction(removal: removal)

        removeToken(.asset("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"))
        #expect(removal.attempt != nil)

        await removal.run(removal.attempt)
        #expect(portfolio.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
    }

    /// Native SOL isn't part of the token list, so removing it starts nothing.
    @Test func `Removing native SOL starts nothing`() {
        let removal = TokenRemovalModel(coordinator: RecordingPortfolio())
        let removeToken = TokenRemovalAction(removal: removal)

        removeToken(.nativeSOL)
        #expect(removal.attempt == nil)
    }
}
