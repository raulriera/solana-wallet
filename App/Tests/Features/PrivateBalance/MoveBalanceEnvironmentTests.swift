import SwiftUI
import Testing
@testable import widgets

@MainActor
struct MoveBalanceEnvironmentTests {
    @Test func `Moving SOL is unavailable outside SOL's details`() {
        #expect(EnvironmentValues().moveBalance == nil)
    }
}
