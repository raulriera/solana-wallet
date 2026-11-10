import SwiftUI
import Testing
@testable import widgets

@MainActor
struct DismissParentContainerEnvironmentTests {
    @Test func `Dismissing the parent container is unavailable outside one`() {
        #expect(EnvironmentValues().dismissParentContainer == nil)
    }
}
