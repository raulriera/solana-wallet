import SwiftUI
import Testing
@testable import widgets

@MainActor
struct KeypadStyleEnvironmentTests {
    @Test func `Keypad style starts with the app's defaults`() {
        #expect(EnvironmentValues().keypadStyle == KeypadStyle())
    }
}
