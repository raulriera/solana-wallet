import Testing
@testable import widgets

/// Checks the section names that each window saves with its scene state.
struct WalletSectionTests {
    /// Saved names stay valid across app updates, so a renamed case would reset every restored window.
    /// - Parameters:
    ///   - section: A wallet window's section.
    ///   - saved: The name saved with the window's scene state.
    @Test(arguments: [(WalletSection.portfolio, "portfolio"), (.settings, "settings")])
    func `Each section keeps its saved name`(section: WalletSection, saved: String) {
        #expect(section.rawValue == saved)
        #expect(WalletSection(rawValue: saved) == section)
    }
}
