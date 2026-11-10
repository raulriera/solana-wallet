import SwiftUI
import Testing
@testable import widgets

@MainActor
struct NewPaymentEnvironmentTests {
    @Test func `New payment is unavailable outside Contacts`() {
        #expect(EnvironmentValues().newPayment == nil)
    }
}
