import Foundation
import Testing
@testable import widgets

struct AccountsRouteTests {
    @Test
    func `Each account has its own route`() {
        let id = UUID()

        #expect(AccountsRoute.account(id) == .account(id))
        #expect(AccountsRoute.account(id) != .account(UUID()))
    }
}
