import SwiftUI
import Testing
@testable import widgets

/// Checks the account creation that a view reads outside a window.
@MainActor
struct AccountCreationEnvironmentTests {
    /// Outside a window, as in previews, no account can be created.
    @Test func `Account creation is unavailable outside a window`() {
        #expect(EnvironmentValues().accountCreation == nil)
    }
}
