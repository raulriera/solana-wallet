import Testing
@testable import widgets

/// Verifies the original appearance that launch depends on.
struct OriginalAppearanceTests {
    /// The app bundle ships the original theme's package, which launch requires.
    @Test
    func `The app bundle includes the original theme`() {
        #expect(OriginalAppearance.packageURL != nil)
    }
}
