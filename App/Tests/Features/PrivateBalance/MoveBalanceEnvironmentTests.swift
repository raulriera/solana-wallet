import SwiftUI
import Testing
@testable import widgets

/// Checks the balance move action a view reads outside SOL's details.
@MainActor
struct MoveBalanceEnvironmentTests {
    /// Outside SOL's details no move can open, so there's no action.
    @Test func `Moving SOL is unavailable outside SOL's details`() {
        #expect(EnvironmentValues().moveBalance == nil)
    }
}
