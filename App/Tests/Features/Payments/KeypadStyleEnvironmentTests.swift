import SwiftUI
import Testing
@testable import widgets

/// Checks the payment keypad options a view reads before a theme chooses any.
@MainActor
struct KeypadStyleEnvironmentTests {
    /// Without a theme, the keypad uses the app's default options.
    @Test func `Keypad style starts with the app's defaults`() {
        #expect(EnvironmentValues().keypadStyle == KeypadStyle())
    }
}
