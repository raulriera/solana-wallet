import Foundation
import UIKit
import XCTest

@MainActor
struct OnboardingApp {
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private static let recoveryGuidance = "Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet."
    private static let setupErrorTitles = ["Wallet Setup Unavailable", "Too Many Requests", "Couldn't Connect",
                                           "Couldn't Save API Key", "Couldn't Load Provider", "Couldn't Change Provider"]

    private enum FlowError: Error { case missingElement, unexpectedElement, unavailableControl, reportedError, missingConfiguration }

    let app = XCUIApplication()

    var submitImport: XCUIElement { app.buttons["Import Wallet"] }
    var backupConfirmation: XCUIElement { app.alerts["Have you saved your recovery words?"] }
    var portfolioTab: XCUIElement { app.buttons["Portfolio"].firstMatch }
    var settingsTab: XCUIElement { app.buttons["Settings"].firstMatch }
    var keySheet: XCUIElement { app.navigationBars["Connect to Helius"] }

    init() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func launch() throws {
        app.launchEnvironment["UI_TEST_RESET"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "UI_TEST_RESET")
        try expectWelcome()
    }

    func relaunch() {
        app.terminate()
        app.launch()
    }

    func expectWelcome() throws {
        try waitFor(app.buttons["Create Wallet"])
    }

    func expectWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(portfolioTab, label: "Portfolio", file: file, line: line)
    }

    func expectProviders(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(app.navigationBars["Providers"], label: "Providers", file: file, line: line)
        try waitFor(app.staticTexts["Step 2 of 2"], file: file, line: line)
        try waitForAbsence(app.buttons["BackButton"], file: file, line: line)
    }

    func createWallet() throws {
        try tap(app.buttons["Create Wallet"])
        try expectRecovery()
        try tap(app.buttons["Continue"])
        try waitFor(backupConfirmation)
        try tap(backupConfirmation.buttons["Yes"])
        try expectProviders()
        try waitForAbsence(app.staticTexts[Self.recoveryGuidance])
    }

    func expectKeyRejected(file: StaticString = #filePath, line: UInt = #line) throws {
        let message = "Your provider didn't accept this API key. Check it and try again."
        try expectSetupOutcome(app.staticTexts[message], label: message, file: file, line: line)
    }

    func chooseHelius(file: StaticString = #filePath, line: UInt = #line) throws {
        try tap(app.buttons["Helius"], file: file, line: line)
        try expectSetupOutcome(keySheet, label: "Connect to Helius", file: file, line: line)
    }

    func frontButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try XCTUnwrap(app.buttons.matching(identifier: label).allElementsBoundByIndex.first(where: \.isHittable),
                      "No tappable \(label) button", file: file, line: line)
    }

    func paste(_ text: String) throws {
        UIPasteboard.general.string = text
        try tap(app.buttons["Paste"])
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "pasted from")).firstMatch
        _ = banner.waitForExistence(timeout: 2)
        try waitForAbsence(banner)
    }

    static func holdingLabel(beginningWith prefix: String) -> NSPredicate {
        NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@", XCUIElement.ElementType.button.rawValue, prefix)
    }

    func holding(_ prefix: String) -> XCUIElement {
        app.buttons.matching(Self.holdingLabel(beginningWith: prefix)).firstMatch
    }

    func submitProviderKey(_ key: String) throws {
        let field = app.secureTextFields["RPC API key"]
        try tap(field)
        field.typeText(key)
        try tap(try frontButton("Continue"))
    }

    func openWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try tap(app.buttons["Continue"], file: file, line: line)
        try showPortfolio(file: file, line: line)
    }

    func showPortfolio(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectWallet(file: file, line: line)
        try tap(portfolioTab, file: file, line: line)
    }

    func openSecurity(file: StaticString = #filePath, line: UInt = #line) throws {
        try tap(settingsTab, file: file, line: line)
        try tap(app.buttons["Security & Privacy"], file: file, line: line)
    }

    func connectProvider(file: StaticString = #filePath, line: UInt = #line) throws {
        guard let key = ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
              !key.isEmpty, !key.hasPrefix("$(") else {
            XCTFail("HELIUS_API_KEY must be configured for UI tests", file: file, line: line)
            throw FlowError.missingConfiguration
        }
        try chooseHelius(file: file, line: line)
        try submitProviderKey(key)
        try showPortfolio(file: file, line: line)
    }

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

    func openImport() throws {
        try tap(app.buttons["Import Wallet"])
        try waitFor(app.secureTextFields["Recovery words"])
        try waitFor(app.staticTexts["Step 1 of 2"])
    }

    func enterPhrase(_ phrase: String = Self.phrase) throws {
        let field = app.secureTextFields["Recovery words"]
        try tap(field)
        field.typeText(phrase + "\n")
    }

    func enterPassphrase(_ passphrase: String) throws {
        let field = app.secureTextFields["BIP-39 passphrase, optional"]
        if !field.isHittable { app.swipeUp() }
        try tap(field)
        field.typeText(passphrase + "\n")
    }

    private func expectSetupOutcome(_ destination: XCUIElement, label: String,
                                    file: StaticString, line: UInt) throws {
        try expectOutcome(destination, matching: NSPredicate(format: "label == %@", label),
                          unless: Self.setupErrorTitles, file: file, line: line)
    }

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

    func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Expected onboarding UI did not appear", file: file, line: line)
            throw FlowError.missingElement
        }
    }

    func waitForAbsence(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForNonExistence(timeout: 10) else {
            XCTFail("Onboarding UI that should be gone is still on screen", file: file, line: line)
            throw FlowError.unexpectedElement
        }
    }

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
