import SwiftUI
import Testing
@testable import widgets

/// Checks the token presentation options a view reads before a theme chooses any.
@MainActor
struct CardStyleEnvironmentTests {
    /// Without a theme, the portfolio uses the app's default options.
    @Test func `Card style starts with the app's defaults`() {
        #expect(EnvironmentValues().cardStyle == CardStyle())
    }
}
