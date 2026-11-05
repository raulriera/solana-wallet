import XCTest

@MainActor
final class ImportWalletUITests: XCTestCase {
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

        XCUIApplication(bundleIdentifier: "com.apple.springboard").activate()
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
        try flow.waitFor(flow.app.textFields.matching(NSPredicate(format: "value == %@", OnboardingApp.phrase)).firstMatch)
        let passphrase = flow.app.secureTextFields["BIP-39 passphrase, optional"]
        if !passphrase.isHittable { flow.app.swipeUp() }
        try flow.waitFor(passphrase)
        XCTAssertNotEqual(try XCTUnwrap(passphrase.value as? String), "Optional")
    }

    @objc(testRevealPassphraseAndReturnError:)
    func `test The passphrase can be revealed to check it exactly`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        try flow.enterPhrase()
        try flow.enterPassphrase(" TrEzOr ")

        try flow.tap(flow.app.buttons["Show passphrase"])

        let revealed = flow.app.textFields["BIP-39 passphrase, optional"]
        try flow.waitFor(revealed)
        XCTAssertEqual(revealed.value as? String, " TrEzOr ")
        try flow.tap(flow.app.buttons["Hide passphrase"])
        let hidden = flow.app.secureTextFields["BIP-39 passphrase, optional"]
        try flow.waitFor(hidden)
        XCTAssertNotEqual(hidden.value as? String, "Optional")
    }

    @objc(testImportWithPassphraseRestoresAfterRelaunchAndReturnError:)
    func `test Import with an original passphrase completes and restores after relaunch`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        try flow.enterPhrase()
        try flow.enterPassphrase(" TrEzOr ")

        try flow.tap(flow.submitImport)

        try flow.expectRPC()
        XCTAssertFalse(flow.backupConfirmation.exists)
        try flow.openWallet()
        flow.relaunch()
        try flow.expectWallet()
        XCTAssertFalse(flow.app.buttons["Import Wallet"].exists)
    }
}
