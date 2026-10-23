import SwiftUI
import Testing
@testable import widgets

/// Checks the token removal action a view reads outside the portfolio.
@MainActor
struct RemoveTokenEnvironmentTests {
    /// Outside the portfolio no token can be removed, so there's no action.
    @Test func `Token removal is unavailable outside the portfolio`() {
        #expect(EnvironmentValues().removeToken == nil)
    }
}
