import Foundation
import UIKit
import XCTest

/// Drives production onboarding, resetting real app state once per scenario and retaining it across relaunches.
@MainActor
struct OnboardingApp {
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private static let recoveryGuidance = "Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet."
    /// The titles of the alerts that report a wallet setup, provider choice, or provider key error.
    private static let setupErrorTitles = ["Wallet Setup Unavailable", "Too Many Requests", "Couldn't Connect",
                                           "Couldn't Save API Key", "Couldn't Load Provider", "Couldn't Change Provider"]

    /// Stops dependent interactions after a checked UI wait fails.
    private enum FlowError: Error { case missingElement, unexpectedElement, unavailableControl, reportedError, missingConfiguration }

    let app = XCUIApplication()

    var submitImport: XCUIElement { app.buttons["Import Wallet"] }
    var backupConfirmation: XCUIElement { app.alerts["Have you saved your recovery words?"] }
    /// The wallet's Portfolio tab, in the bottom tab bar on iPhone and the top one on iPad, which isn't a tab bar element.
    var portfolioTab: XCUIElement { app.buttons["Portfolio"].firstMatch }
    /// The wallet's Settings tab, found the same way as the Portfolio tab.
    var settingsTab: XCUIElement { app.buttons["Settings"].firstMatch }
    var keySheet: XCUIElement { app.navigationBars["Connect to Helius"] }

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

    /// Confirms that saving the wallet pushed the provider choice as the last step, with no way back to the wallet's
    /// earlier steps.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing provider choice or step count, a remaining back button, or an explicit wallet setup failure.
    func expectProviders(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(app.navigationBars["Providers"], label: "Providers", file: file, line: line)
        try waitFor(app.staticTexts["Step 2 of 2"], file: file, line: line)
        // The outgoing step's back button leaves when the push finishes; the provider choice has none.
        try waitForAbsence(app.buttons["BackButton"], file: file, line: line)
    }

    /// Creates a disposable, unfunded wallet through onboarding and waits for the provider choice.
    /// - Throws: A missing or unavailable control, or an explicit wallet setup failure.
    func createWallet() throws {
        try tap(app.buttons["Create Wallet"])
        try expectRecovery()
        try tap(app.buttons["Continue"])
        try waitFor(backupConfirmation)
        try tap(backupConfirmation.buttons["Yes"])
        try expectProviders()
        try waitForAbsence(app.staticTexts[Self.recoveryGuidance])
    }

    /// Confirms that the provider rejected the entered key, failing immediately if the app reports another error.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing rejection message or an explicit wallet setup failure.
    func expectKeyRejected(file: StaticString = #filePath, line: UInt = #line) throws {
        let message = "Your provider didn't accept this API key. Check it and try again."
        try expectSetupOutcome(app.staticTexts[message], label: message, file: file, line: line)
    }

    /// Chooses Helius on the provider choice and waits for its key sheet, failing immediately if the app reports an
    /// error instead.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing or unavailable control, a missing key sheet, or an explicit setup failure.
    func chooseHelius(file: StaticString = #filePath, line: UInt = #line) throws {
        try tap(app.buttons["Helius"], file: file, line: line)
        try expectSetupOutcome(keySheet, label: "Connect to Helius", file: file, line: line)
    }

    /// The button with this label that a person can tap; a button behind a sheet shares its label but can't be tapped.
    /// - Parameters:
    ///   - label: The button's label, such as "Continue" on both a sheet and the screen behind it.
    ///   - file: The caller's source file for failure reporting.
    ///   - line: The caller's source line for failure reporting.
    /// - Returns: The front button.
    /// - Throws: A missing button after recording the failed assertion.
    func frontButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try XCTUnwrap(app.buttons.matching(identifier: label).allElementsBoundByIndex.first(where: \.isHittable),
                      "No tappable \(label) button", file: file, line: line)
    }

    /// Puts text on the clipboard and pastes it with the screen's Paste button, then waits for the system's
    /// "pasted from" banner to leave, since on iPhone it covers the top bar's buttons and takes their taps.
    /// - Parameter text: Public test input, which stays on the clipboard.
    /// - Throws: A missing or unavailable Paste button, or a banner that stays.
    func paste(_ text: String) throws {
        UIPasteboard.general.string = text
        try tap(app.buttons["Paste"])
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "pasted from")).firstMatch
        // The banner appears a moment after the paste, so wait for it before waiting for it to leave.
        _ = banner.waitForExistence(timeout: 2)
        try waitForAbsence(banner)
    }

    /// Matches a portfolio holding's button by the start of its label, such as the token's symbol.
    /// - Parameter prefix: The start of the holding's label.
    /// - Returns: A predicate for the holding's button.
    static func holdingLabel(beginningWith prefix: String) -> NSPredicate {
        NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@", XCUIElement.ElementType.button.rawValue, prefix)
    }

    /// The first portfolio holding whose label starts with a prefix, such as the token's symbol.
    /// - Parameter prefix: The start of the holding's label.
    /// - Returns: The holding's button.
    func holding(_ prefix: String) -> XCUIElement {
        app.buttons.matching(Self.holdingLabel(beginningWith: prefix)).firstMatch
    }

    /// Types a provider key into the key sheet and submits it once.
    /// - Parameter key: The configured key, or a dummy key the provider rejects.
    /// - Throws: A missing or unavailable control.
    func submitProviderKey(_ key: String) throws {
        let field = app.secureTextFields["RPC API key"]
        try tap(field)
        field.typeText(key)
        try tap(try frontButton("Continue"))
    }

    /// Opens the saved wallet with the provider in use, waits for it, and shows its portfolio.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing or unavailable control, or an explicit wallet setup failure.
    func openWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try tap(app.buttons["Continue"], file: file, line: line)
        try showPortfolio(file: file, line: line)
    }

    /// Waits for the saved wallet and shows its portfolio.
    ///
    /// The window can restore the tab it showed before the reset that started the test, so the portfolio is selected.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing or unavailable control, or an explicit wallet setup failure.
    func showPortfolio(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectWallet(file: file, line: line)
        try tap(portfolioTab, file: file, line: line)
    }

    /// Chooses Helius with the key from ignored local configuration, which opens the wallet once Helius is chosen.
    /// - Parameters:
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing key, a missing or unavailable control, or an explicit wallet setup failure.
    func connectProvider(file: StaticString = #filePath, line: UInt = #line) throws {
        guard let key = ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
              !key.isEmpty, !key.hasPrefix("$(") else {
            XCTFail("HELIUS_API_KEY must be configured for UI tests", file: file, line: line)
            throw FlowError.missingConfiguration
        }
        try chooseHelius(file: file, line: line)
        try submitProviderKey(key)
        // The sheet closes once the key is saved, Helius is chosen after it, and the wallet opens; a check or save that
        // fails shows an alert, which ends the wait at once.
        try showPortfolio(file: file, line: line)
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
            throw FlowError.missingElement
        }
    }

    /// Opens the existing import screen through its welcome action as the first step.
    /// - Throws: A missing or unavailable control, or a missing step count.
    func openImport() throws {
        try tap(app.buttons["Import Wallet"])
        try waitFor(app.secureTextFields["Recovery words"])
        try waitFor(app.staticTexts["Step 1 of 2"])
    }

    /// Enters public fixture words and leaves the field with the keyboard's Next key, which checks them.
    /// - Parameter phrase: Public test input, never real wallet recovery.
    /// - Throws: A missing or unavailable control.
    func enterPhrase(_ phrase: String = Self.phrase) throws {
        let field = app.secureTextFields["Recovery words"]
        try tap(field)
        field.typeText(phrase + "\n")
    }

    /// Enters a public fixture's original passphrase without transforming its case or whitespace, then closes the
    /// keyboard with its Done key.
    /// - Parameter passphrase: The public fixture passphrase.
    /// - Throws: A missing or unavailable control.
    func enterPassphrase(_ passphrase: String) throws {
        let field = app.secureTextFields["BIP-39 passphrase, optional"]
        if !field.isHittable { app.swipeUp() }
        try tap(field)
        field.typeText(passphrase + "\n")
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
        try expectOutcome(destination, matching: NSPredicate(format: "label == %@", label),
                          unless: Self.setupErrorTitles, file: file, line: line)
    }

    /// Waits for an expected element, failing immediately when the app shows one of the named alerts instead.
    /// - Parameters:
    ///   - destination: The expected element.
    ///   - outcome: Matches the expected element, so the wait also ends when an alert appears.
    ///   - alerts: The titles of the alerts that report a failure.
    ///   - file: The calling test's source file for failure reporting.
    ///   - line: The calling test's line for failure reporting.
    /// - Throws: A missing destination, or the failure the app reported.
    func expectOutcome(_ destination: XCUIElement, matching outcome: NSPredicate, unless alerts: [String],
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let reports = alerts.map { NSPredicate(format: "label == %@", $0) }
        let either = NSCompoundPredicate(orPredicateWithSubpredicates: [outcome] + reports)
        try waitFor(app.descendants(matching: .any).matching(either).firstMatch, file: file, line: line)
        if let alert = alerts.first(where: { app.alerts[$0].exists }) {
            XCTFail("The app reported \(alert) instead of the expected result.", file: file, line: line)
            throw FlowError.reportedError
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
            throw FlowError.missingElement
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
            throw FlowError.unexpectedElement
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
            throw FlowError.unavailableControl
        }
        element.tap()
    }
}
