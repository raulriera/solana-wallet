import SwiftUI
import Testing
@testable import widgets

@MainActor
struct PressKeyEnvironmentTests {
    @Test func `Key presses are unavailable outside the keypad screen`() {
        #expect(EnvironmentValues().pressKey == nil)
    }
}
