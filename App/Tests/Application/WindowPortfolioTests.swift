import Portfolio
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Checks that a window's portfolio follows the window's network: a new network gets its own coordinator and token
/// removals, and its shared service exists only once a window shows it.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowPortfolioTests {
    private static let bonk = Holding(id: .asset("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"), amount: nil,
                                      name: "Bonk", symbol: "Bonk", imageURL: nil, valuation: nil)

    /// A mainnet window creates no devnet service; switching to devnet creates it and replaces the coordinator and
    /// token removals with devnet's.
    @Test
    func `Switching to devnet replaces the portfolio with devnet's`() {
        var made: [Network] = []
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:]))) { network, _ in
            made.append(network)
            return ProviderChanges()
        }
        let portfolio = WindowPortfolio(network: .mainnet, makeCoordinator: portfolios.makeCoordinator(for:))
        let mainnet = portfolio.coordinator
        let mainnetRemoval = portfolio.tokenRemoval
        #expect(made == [.mainnet])
        #expect(mainnet.network == .mainnet)

        portfolio.show(.devnet)

        #expect(made == [.mainnet, .devnet])
        #expect(portfolio.coordinator.network == .devnet)
        #expect(portfolio.coordinator !== mainnet)
        #expect(portfolio.tokenRemoval !== mainnetRemoval)
    }

    /// After a switch, a confirmed removal edits the new network's token list and leaves the previous network's list
    /// alone.
    @Test
    func `Removals after a switch edit the new network's list`() async throws {
        let portfolio = WindowPortfolio(network: .mainnet) { RecordingPortfolio(network: $0) }
        let mainnet = try #require(portfolio.coordinator as? RecordingPortfolio)

        portfolio.show(.devnet)
        let devnet = try #require(portfolio.coordinator as? RecordingPortfolio)
        portfolio.tokenRemoval.remove(Self.bonk)
        await portfolio.tokenRemoval.run(portfolio.tokenRemoval.attempt)

        #expect(devnet.network == .devnet)
        #expect(devnet.removed.map(\.value) == ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"])
        #expect(mainnet.removed.isEmpty)
    }
}
