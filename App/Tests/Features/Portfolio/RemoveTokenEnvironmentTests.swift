import SwiftUI
import Testing
@testable import widgets

@MainActor
struct RemoveTokenEnvironmentTests {
    @Test func `Token removal is unavailable outside the portfolio`() {
        #expect(EnvironmentValues().removeToken == nil)
    }
}
