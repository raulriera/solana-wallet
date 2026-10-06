import Foundation
import XCTest

/// Drives production onboarding, resetting real app state once per scenario and retaining it across relaunches.
@MainActor
struct OnboardingApp {
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private static let recoveryGuidance = "Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet."

    /// Stops dependent interactions after a checked UI wait fails.
    private enum Failure: Error { case missingElement, unexpectedElement, unavailableControl, walletSetupFailed, missingConfiguration }

    let app = XCUIApplication()

    var submitImport: XCUIElement { app.buttons["Import Wallet"] }
    var backupConfirmation: XCUIElement { app.alerts["Have you saved your recovery words?"] }
    var portfolioTab: XCUIElement { app.tabBars.buttons["Portfolio"] }

    /// Selects the language used by the test's user-facing control queries.
    init() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// Clears the simulator app's actual stores, then runs production startup and waits for welcome.
    /// - Throws: A UI readiness failure.
    func launch() throws {
        app.launchEnvironment["UI_TEST_RESET"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "UI_TEST_RESET")
        try expectWelcome()
    }

    /// Restarts the process without resetting storage so saved wallets must restore normally.
    func relaunch() {
        app.terminate()
        app.launch()
    }

    /// Confirms startup resolved to the onboarding choices.
    /// - Throws: A missing welcome control.
    func expectWelcome() throws {
        try waitFor(app.buttons["Create Wallet"])
    }

    /// Confirms that the window shows the wallet destination.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing wallet destination or an explicit wallet setup failure.
    func expectWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(portfolioTab, label: "Portfolio", file: file, line: line)
    }

    /// Confirms that saving the wallet pushed provider setup as the last step, with no way back to the wallet's earlier steps.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing provider setup destination or step count, a remaining back button, or an explicit wallet setup failure.
    func expectProviderSetup(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(app.navigationBars["Connect to Helius"], label: "Connect to Helius", file: file, line: line)
        try waitFor(app.staticTexts["Step 2 of 2"], file: file, line: line)
        // The outgoing step's back button leaves when the push finishes; provider setup has none.
        try waitForAbsence(app.buttons["BackButton"], file: file, line: line)
    }

    /// Creates a disposable, unfunded wallet through onboarding and waits for provider setup.
    /// - Throws: A missing or unavailable control, or an explicit wallet setup failure.
    func createWallet() throws {
        try tap(app.buttons["Create Wallet"])
        try expectRecovery()
        try tap(app.buttons["Continue"])
        try waitFor(backupConfirmation)
        try tap(backupConfirmation.buttons["Yes"])
        try expectProviderSetup()
        try waitForAbsence(app.staticTexts[Self.recoveryGuidance])
    }

    /// Confirms that Helius rejected the entered key, failing immediately if the app reports another error.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing rejection message or an explicit wallet setup failure.
    func expectKeyRejected(file: StaticString = #filePath, line: UInt = #line) throws {
        let message = "Helius didn't accept this API key. Check it and try again."
        try expectSetupOutcome(app.staticTexts[message], label: message, file: file, line: line)
    }

    /// Types a provider key into the setup screen and submits it once.
    /// - Parameter key: The configured key, or a dummy key the provider rejects.
    /// - Throws: A missing or unavailable control.
    func submitProviderKey(_ key: String) throws {
        let field = app.secureTextFields["Helius API key"]
        try tap(field)
        field.typeText(key)
        try tap(app.buttons["Continue"])
    }

    /// Connects with the Helius key from ignored local configuration and waits for the wallet.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing key, a missing or unavailable control, or an explicit wallet setup failure.
    func connectProvider(file: StaticString = #filePath, line: UInt = #line) throws {
        guard let key = ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
              !key.isEmpty, !key.hasPrefix("$(") else {
            XCTFail("HELIUS_API_KEY must be configured for UI tests", file: file, line: line)
            throw Failure.missingConfiguration
        }
        try submitProviderKey(key)
        try expectWallet(file: file, line: line)
    }

    /// Checks the production creation screen as the first step and its twelve numbered words without expecting a fixed phrase.
    /// - Throws: A missing recovery destination, step count, or word row.
    func expectRecovery() throws {
        try waitFor(app.navigationBars["Recovery Phrase"])
        try waitFor(app.staticTexts["Step 1 of 2"])
        try waitFor(app.staticTexts[Self.recoveryGuidance])
        let lastWord = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"12\. [a-z]+"#))
        try waitFor(lastWord.firstMatch)
        let words = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"([1-9]|1[0-2])\. [a-z]+"#))
        guard words.count == 12 else {
            XCTFail("Recovery must expose twelve numbered word labels")
            throw Failure.missingElement
        }
    }

    /// Opens the existing import screen through its welcome action as the first step.
    /// - Throws: A missing or unavailable control, or a missing step count.
    func openImport() throws {
        try tap(app.buttons["Import Wallet"])
        try waitFor(app.secureTextFields["Recovery words"])
        try waitFor(app.staticTexts["Step 1 of 2"])
    }

    /// Enters public fixture words and dismisses the keyboard through the screen's native toolbar.
    /// - Parameter phrase: Public test input, never real wallet recovery.
    /// - Throws: A missing or unavailable control.
    func enterPhrase(_ phrase: String = Self.phrase) throws {
        let field = app.secureTextFields["Recovery words"]
        try tap(field)
        field.typeText(phrase)
        try tap(app.toolbars.buttons["Done"])
    }

    /// Enters a public fixture's original passphrase without transforming its case or whitespace.
    /// - Parameter passphrase: The public fixture passphrase.
    /// - Throws: A missing or unavailable control.
    func enterPassphrase(_ passphrase: String) throws {
        let field = app.secureTextFields["BIP-39 passphrase, optional"]
        if !field.isHittable { app.swipeUp() }
        try tap(field)
        field.typeText(passphrase)
        try tap(app.toolbars.buttons["Done"])
    }

    /// Waits for a setup destination, failing immediately when the app reports a setup error instead.
    /// - Parameters:
    ///   - destination: The element that identifies the expected destination.
    ///   - label: The destination's label that ends the wait alongside the error alert.
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing destination or an explicit wallet setup failure.
    private func expectSetupOutcome(_ destination: XCUIElement, label: String,
                                    file: StaticString, line: UInt) throws {
        let outcome = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN %@", [label, "Wallet Setup Unavailable"])
        ).firstMatch
        try waitFor(outcome, file: file, line: line)
        guard !app.alerts["Wallet Setup Unavailable"].exists else {
            XCTFail("The app reported Wallet Setup Unavailable instead of completing wallet setup.", file: file, line: line)
            throw Failure.walletSetupFailed
        }
        try waitFor(destination, file: file, line: line)
    }

    /// Waits for a required element and stops this test's dependent interactions on timeout.
    /// - Parameters:
    ///   - element: A control or destination selected by its user-facing text or accessibility label.
    ///   - file: The caller's source file for failure reporting.
    ///   - line: The caller's source line for failure reporting.
    /// - Throws: A missing-element failure after recording the failed assertion.
    func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Expected onboarding UI did not appear", file: file, line: line)
            throw Failure.missingElement
        }
    }

    /// Waits for an element to leave the screen and stops this test's dependent interactions if it stays.
    /// - Parameters:
    ///   - element: A control or text that must be gone, such as the outgoing step during a push.
    ///   - file: The caller's source file for failure reporting.
    ///   - line: The caller's source line for failure reporting.
    /// - Throws: An unexpected-element failure after recording the failed assertion.
    func waitForAbsence(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForNonExistence(timeout: 10) else {
            XCTFail("Onboarding UI that should be gone is still on screen", file: file, line: line)
            throw Failure.unexpectedElement
        }
    }

    /// Waits for an enabled, hittable control and taps it exactly once.
    /// - Parameters:
    ///   - element: The intended control; persistence actions are never blindly retried.
    ///   - file: The caller's source file for failure reporting.
    ///   - line: The caller's source line for failure reporting.
    /// - Throws: A readiness failure after recording the failed assertion.
    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        let predicate = NSPredicate(format: "exists == true AND isHittable == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: 10) == .completed else {
            XCTFail("Expected onboarding control did not become ready", file: file, line: line)
            throw Failure.unavailableControl
        }
        element.tap()
    }
}
