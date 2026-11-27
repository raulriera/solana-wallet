import XCTest

@MainActor
final class ImportWalletUITests: XCTestCase {
    private static let passphrase = " TrEzOr "

    @objc(testInvalidRecoveryDoesNotPersistAndReturnError:)
    func `test Invalid recovery displays an inline error without persisting a wallet`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.openImport()
        XCTAssertFalse(onboarding.importWalletButton.isEnabled)

        try onboarding.enterPhrase(OnboardingPage.invalidPhrase)
        try app.tap(onboarding.importWalletButton)

        try app.waitFor(onboarding.invalidRecoveryError)
        XCTAssertFalse(onboarding.backupConfirmation.exists)
        XCTAssertFalse(app.portfolioTab.exists)
        app.relaunch()
        try onboarding.expectWelcome()
    }

    @objc(testBackgroundConcealsRecoveryWithoutLosingInputAndReturnError:)
    func `test Returning from the background hides recovery without losing input`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.openImport()
        try onboarding.enterPhrase()
        try onboarding.enterPassphrase(Self.passphrase)
        app.reveal(onboarding.showWordsButton, swiping: .down)
        try app.tap(onboarding.showWordsButton)
        try app.waitFor(onboarding.hideWordsButton)

        try app.returnFromBackground()

        try app.waitFor(onboarding.recoveryWords)
        try app.waitFor(onboarding.showWordsButton)
        XCTAssertFalse(onboarding.hideWordsButton.exists)
        XCTAssertTrue(onboarding.importWalletButton.isEnabled)
        try app.tap(onboarding.showWordsButton)
        try app.waitFor(onboarding.hideWordsButton)
        try app.waitFor(onboarding.revealedRecoveryWords)
        app.reveal(onboarding.passphrase, swiping: .up)
        try app.waitFor(onboarding.passphrase)
        XCTAssertFalse(onboarding.passphraseIsEmpty)
    }

    @objc(testImportWithPassphraseRestoresAfterRelaunchAndReturnError:)
    func `test Import with an original passphrase completes and restores after relaunch`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.openImport()
        try onboarding.enterPhrase()
        try onboarding.enterPassphrase(Self.passphrase)

        try app.tap(onboarding.importWalletButton)

        try onboarding.expectRPC()
        XCTAssertFalse(onboarding.backupConfirmation.exists)
        try onboarding.openWallet()
        app.relaunch()
        try onboarding.expectWallet()
        XCTAssertFalse(onboarding.importWalletButton.exists)
    }
}
