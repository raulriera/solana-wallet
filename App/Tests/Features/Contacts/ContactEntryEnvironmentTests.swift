import SwiftUI
import Testing
@testable import widgets

/// Checks the contact entry action a view reads outside Contacts.
@MainActor
struct ContactEntryEnvironmentTests {
    /// Outside Contacts no recipient sheet can open, so there's no action.
    @Test func `Contact entry is unavailable outside Contacts`() {
        #expect(EnvironmentValues().contactEntry == nil)
    }
}
