import RPC
import Testing
@testable import widgets

/// Checks that a window's private balance follows the network that the window shows.
@MainActor
struct WindowModelTests {
    /// A switch to devnet gives the window a new private balance.
    @Test
    func `Switching to devnet replaces the private balance`() {
        let services = AppServices()
        let window = WindowModel(services: services, network: .mainnet)
        let mainnet = window.privateBalance

        window.show(.devnet)

        #expect(window.privateBalance !== mainnet)
    }
}
