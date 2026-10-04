import Foundation
import XCTest

/// Drives production onboarding, resetting real app state once per scenario and retaining it across relaunches.
@MainActor
struct OnboardingApp {
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    /// Stops dependent interactions after a checked UI wait fails.
    private enum Failure: Error { case missingElement, unavailableControl, walletSetupFailed }

    let app = XCUIApplication()

    var submitImport: XCUIElement { app.buttons["Import Wallet"] }
    var backupConfirmation: XCUIElement { app.alerts["Have you saved your recovery words?"] }

    /// Selects the language used by the test's user-facing control queries.
    init() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UI_TEST_NETWORK"] = "devnet"
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

    /// Confirms that successful persistence handed control to the wallet destination.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing wallet destination or an explicit wallet setup failure.
    func expectWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        let outcome = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Wallet ready", "Wallet Setup Unavailable"])
        ).firstMatch
        try waitFor(outcome, file: file, line: line)
        guard !app.alerts["Wallet Setup Unavailable"].exists else {
            XCTFail("The app reported Wallet Setup Unavailable instead of completing wallet setup.", file: file, line: line)
            throw Failure.walletSetupFailed
        }
        try waitFor(app.staticTexts["Wallet ready"], file: file, line: line)
    }

    /// Checks the production creation screen and its twelve numbered words without expecting a fixed phrase.
    /// - Throws: A missing recovery destination or word row.
    func expectRecovery() throws {
        try waitFor(app.navigationBars["Recovery Phrase"])
        try waitFor(app.staticTexts["Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet."])
        let lastWord = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"12\. [a-z]+"#))
        try waitFor(lastWord.firstMatch)
        let words = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"([1-9]|1[0-2])\. [a-z]+"#))
        guard words.count == 12 else {
            XCTFail("Recovery must expose twelve numbered word labels")
            throw Failure.missingElement
        }
    }

    /// Opens the existing import screen through its welcome action.
    /// - Throws: A missing or unavailable control.
    func openImport() throws {
        try tap(app.buttons["Import Wallet"])
        try waitFor(app.secureTextFields["Recovery words"])
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
