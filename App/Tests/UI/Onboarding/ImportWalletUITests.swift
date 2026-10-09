import XCTest

/// Exercises visible import behavior through XCUIApplication with public recovery fixtures only.
@MainActor
final class ImportWalletUITests: XCTestCase {
    /// Invalid words stay on phrase entry and cannot create a wallet restored by the next launch.
    @objc(testInvalidRecoveryDoesNotPersistAndReturnError:)
    func `test Invalid recovery displays an inline error without persisting a wallet`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        XCTAssertFalse(flow.submitImport.isEnabled)

        try flow.enterPhrase("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon")
        try flow.tap(flow.submitImport)

        let error = flow.app.staticTexts["These words don't form a valid recovery phrase. Check their spelling and order."]
        try flow.waitFor(error)
        XCTAssertFalse(flow.backupConfirmation.exists)
        XCTAssertFalse(flow.portfolioTab.exists)
        flow.relaunch()
        try flow.expectWelcome()
    }

    /// Back discards transient entry, including a revealed phrase and an original passphrase.
    @objc(testBackClearsImportInputAndReturnError:)
    func `test Back returns to welcome and reopening import clears all input`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        try flow.enterPhrase()
        try flow.enterPassphrase(" TrEzOr ")
        let reveal = flow.app.buttons["Show words"]
        if !reveal.isHittable { flow.app.swipeDown() }
        try flow.tap(reveal)
        try flow.waitFor(flow.app.buttons["Hide words"])
        try flow.tap(flow.app.buttons["BackButton"])

        try flow.expectWelcome()
        try flow.openImport()
        XCTAssertFalse(flow.submitImport.isEnabled)
        XCTAssertTrue(flow.app.buttons["Show words"].exists)
        XCTAssertEqual(flow.app.secureTextFields["Recovery words"].value as? String, "Recovery words")
        let passphrase = flow.app.secureTextFields["BIP-39 passphrase, optional"]
        if !passphrase.isHittable { flow.app.swipeUp() }
        try flow.waitFor(passphrase)
        XCTAssertEqual(passphrase.value as? String, "Optional")
    }

    /// Returning from the background conceals revealed recovery while retaining the unfinished entry.
    @objc(testBackgroundConcealsRecoveryWithoutLosingInputAndReturnError:)
    func `test Returning from the background hides recovery without losing input`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        try flow.enterPhrase()
        try flow.enterPassphrase(" TrEzOr ")
        let reveal = flow.app.buttons["Show words"]
        if !reveal.isHittable { flow.app.swipeDown() }
        try flow.tap(reveal)
        try flow.waitFor(flow.app.buttons["Hide words"])

        XCUIDevice.shared.press(.home)
        guard flow.app.wait(for: .runningBackground, timeout: 10) else {
            XCTFail("The app did not enter the background")
            return
        }
        flow.app.activate()
        guard flow.app.wait(for: .runningForeground, timeout: 10) else {
            XCTFail("The app did not return to the foreground")
            return
        }

        try flow.waitFor(flow.app.secureTextFields["Recovery words"])
        try flow.waitFor(reveal)
        XCTAssertFalse(flow.app.buttons["Hide words"].exists)
        XCTAssertTrue(flow.submitImport.isEnabled)
        try flow.tap(reveal)
        try flow.waitFor(flow.app.buttons["Hide words"])
        // The revealed field exposes the words only as its value, without a label.
        try flow.waitFor(flow.app.textFields.matching(NSPredicate(format: "value == %@", OnboardingApp.phrase)).firstMatch)
        let passphrase = flow.app.secureTextFields["BIP-39 passphrase, optional"]
        if !passphrase.isHittable { flow.app.swipeUp() }
        try flow.waitFor(passphrase)
        XCTAssertNotEqual(try XCTUnwrap(passphrase.value as? String), "Optional")
    }

    /// Import bypasses backup confirmation and survives a fresh process through real startup restoration.
    @objc(testImportWithPassphraseRestoresAfterRelaunchAndReturnError:)
    func `test Import with an original passphrase completes and restores after relaunch`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        try flow.enterPhrase()
        try flow.enterPassphrase(" TrEzOr ")

        try flow.tap(flow.submitImport)

        try flow.expectProviderSetup()
        XCTAssertFalse(flow.backupConfirmation.exists)
        try flow.connectProvider()
        flow.relaunch()
        try flow.expectWallet()
        XCTAssertFalse(flow.app.buttons["Import Wallet"].exists)
    }
}
