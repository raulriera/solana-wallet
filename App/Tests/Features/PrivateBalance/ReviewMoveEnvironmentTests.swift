import SwiftUI
import Testing
@testable import widgets

/// Checks the review action a view reads outside a move's keypad.
@MainActor
struct ReviewMoveEnvironmentTests {
    /// Outside a move's keypad nothing can be reviewed, so there's no action.
    @Test func `Reviewing is unavailable outside a move's keypad`() {
        #expect(EnvironmentValues().reviewMove == nil)
    }
}
