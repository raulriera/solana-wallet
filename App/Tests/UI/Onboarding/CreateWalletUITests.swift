import XCTest

@MainActor
final class CreateWalletUITests: XCTestCase {
    @objc(testDecliningBackupDoesNotPersistAndReturnError:)
    func `test Declining backup confirmation stays on recovery and does not persist a wallet`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.tap(flow.app.buttons["Create Wallet"])
        try flow.expectRecovery()
        try flow.tap(flow.app.buttons["Continue"])
        try flow.waitFor(flow.backupConfirmation)

        try flow.tap(flow.backupConfirmation.buttons["No"])

        guard flow.backupConfirmation.waitForNonExistence(timeout: 5) else {
            XCTFail("Backup confirmation did not close")
            return
        }
        try flow.waitFor(flow.app.buttons["Continue"])
        XCTAssertFalse(flow.portfolioTab.exists)
        flow.relaunch()
        try flow.expectWelcome()
    }

    @objc(testConfirmingBackupRestoresAfterRelaunchAndReturnError:)
    func `test Confirming backup completes creation and restores after relaunch`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.tap(flow.app.buttons["Create Wallet"])
        try flow.expectRecovery()
        try flow.tap(flow.app.buttons["Continue"])
        try flow.waitFor(flow.backupConfirmation)

        try flow.tap(flow.backupConfirmation.buttons["Yes"])

        try flow.expectProviders()
        try flow.openWallet()
        flow.relaunch()
        try flow.expectWallet()
        XCTAssertFalse(flow.app.buttons["Create Wallet"].exists)
    }
}
