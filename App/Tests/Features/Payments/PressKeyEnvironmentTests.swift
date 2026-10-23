import SwiftUI
import Testing
@testable import widgets

/// Checks the keypad press action a view reads outside the keypad screen.
@MainActor
struct PressKeyEnvironmentTests {
    /// Outside the keypad screen no amount is typed, so there's no action.
    @Test func `Key presses are unavailable outside the keypad screen`() {
        #expect(EnvironmentValues().pressKey == nil)
    }
}
