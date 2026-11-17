import XCTest

@MainActor
final class RecoveryPhraseUITests: XCTestCase {
    @objc(testShowRecoveryPhraseAfterImportAndReturnError:)
    func `test Security & Privacy shows the imported words, passphrase, and account path`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.openImport()
        try onboarding.enterPhrase()
        try onboarding.enterPassphrase(" TrEzOr ")
        try app.tap(onboarding.importWalletButton)
        try onboarding.expectRPC()
        try onboarding.openWallet()

        let security = try SettingsPage(driver: app).openSecurity()
        try security.showRecoveryPhrase()

        for (position, word) in zip(1..., OnboardingPage.phrase.split(separator: " ")) {
            try app.waitFor(security.recoveryWord(word, at: position))
        }
        app.reveal(security.accountPath, swiping: .up, until: \.exists)
        try app.waitFor(app.text(containing: "TrEzOr"))
        try app.waitFor(security.accountPath)
    }
}
