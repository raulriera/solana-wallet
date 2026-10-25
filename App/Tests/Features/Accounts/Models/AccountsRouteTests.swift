import Foundation
import Testing
@testable import widgets

/// Checks the screens that Settings > Accounts pushes.
struct AccountsRouteTests {
    /// Each account pushes its own screen, so navigation tells two accounts apart.
    @Test
    func `Each account has its own route`() {
        let id = UUID()

        #expect(AccountsRoute.account(id) == .account(id))
        #expect(AccountsRoute.account(id) != .account(UUID()))
    }
}
