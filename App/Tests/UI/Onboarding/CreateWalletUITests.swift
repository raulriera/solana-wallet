import XCTest

@MainActor
final class CreateWalletUITests: XCTestCase {
    @objc(testDecliningBackupDoesNotPersistAndReturnError:)
    func `test Declining backup confirmation stays on recovery and does not persist a wallet`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.reachBackupConfirmation()

        try onboarding.answerBackupConfirmation(saved: false)

        guard onboarding.backupConfirmation.waitForNonExistence(timeout: 5) else {
            XCTFail("Backup confirmation did not close")
            return
        }
        try app.waitFor(onboarding.continueButton)
        XCTAssertFalse(app.portfolioTab.exists)
        app.relaunch()
        try onboarding.expectWelcome()
    }

    @objc(testConfirmingBackupRestoresAfterRelaunchAndReturnError:)
    func `test Confirming backup completes creation and restores after relaunch`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.reachBackupConfirmation()

        try onboarding.answerBackupConfirmation(saved: true)

        try onboarding.expectRPC()
        try onboarding.openWallet()
        app.relaunch()
        try onboarding.expectWallet()
        XCTAssertFalse(onboarding.createWalletButton.exists)
    }
}
