import Testing
@testable import widgets

struct WalletSectionTests {
    @Test(arguments: [(WalletSection.portfolio, "portfolio"), (.settings, "settings")])
    func `Each section keeps its saved name`(section: WalletSection, saved: String) {
        #expect(section.rawValue == saved)
        #expect(WalletSection(rawValue: saved) == section)
    }
}
