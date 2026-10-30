import SwiftUI
import Testing
@testable import widgets

@MainActor
struct ContactEntryEnvironmentTests {
    @Test func `Contact entry is unavailable outside Contacts`() {
        #expect(EnvironmentValues().contactEntry == nil)
    }
}
