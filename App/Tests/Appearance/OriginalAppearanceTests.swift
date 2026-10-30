import Testing
@testable import widgets

struct OriginalAppearanceTests {
    @Test
    func `The app bundle includes the original theme`() {
        #expect(OriginalAppearance.packageURL != nil)
    }
}
