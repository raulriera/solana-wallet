import RPC
import Testing
@testable import widgets

/// Checks that a window's portfolio follows the network that the window shows.
@MainActor
struct WindowModelTests {
    /// A switch to devnet creates devnet's shared service and gives the window a new coordinator and token removals.
    @Test
    func `Switching to devnet replaces the portfolio and its token removals`() {
        let services = AppServices()
        let window = WindowModel(services: services, network: .mainnet)
        let mainnet = window.portfolio
        let mainnetRemoval = window.tokenRemoval
        #expect(services.portfolios.created.count == 1)

        window.show(.devnet)

        #expect(services.portfolios.created.count == 2)
        #expect(window.portfolio !== mainnet)
        #expect(window.tokenRemoval !== mainnetRemoval)
    }
}
