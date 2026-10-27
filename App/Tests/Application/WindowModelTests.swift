import RPC
import Testing
@testable import widgets

/// Checks that a window's portfolio follows the network that the window shows.
@MainActor
struct WindowModelTests {
    /// A switch to devnet gives the window a new coordinator and token removals.
    @Test
    func `Switching to devnet replaces the portfolio and its token removals`() {
        let services = AppServices()
        let window = WindowModel(services: services, network: .mainnet)
        let mainnet = window.portfolio
        let mainnetRemoval = window.tokenRemoval

        window.show(.devnet)

        #expect(window.portfolio !== mainnet)
        #expect(window.tokenRemoval !== mainnetRemoval)
    }
}
