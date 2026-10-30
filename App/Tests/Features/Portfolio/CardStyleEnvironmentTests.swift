import SwiftUI
import Testing
@testable import widgets

@MainActor
struct CardStyleEnvironmentTests {
    @Test func `Card style starts with the app's defaults`() {
        #expect(EnvironmentValues().cardStyle == CardStyle())
    }
}
