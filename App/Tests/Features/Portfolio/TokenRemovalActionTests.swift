import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
struct TokenRemovalActionTests {
    @Test func `Removing a token starts its removal`() async throws {
        let service = PortfolioResponses()
        let removal = TokenRemovalModel()
        let removeToken = TokenRemovalAction(removal: removal)

        removeToken(try Address("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"))
        #expect(removal.attempt != nil)

        await removal.run(removal.attempt, in: .serving(service), for: try .fixture(index: 1), on: .devnet)
        #expect(await service.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
    }
}
