import SwiftUI
import Testing
@testable import widgets

@MainActor
struct AccountCreationEnvironmentTests {
    @Test func `Account creation is unavailable outside a window`() {
        #expect(EnvironmentValues().accountCreation == nil)
    }
}
