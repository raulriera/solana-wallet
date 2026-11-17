import Foundation
import XCTest

@MainActor
struct OnboardingPage {
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    static let invalidPhrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"
    private static let recoveryGuidance = "Write down these words in order and keep them somewhere safe. Anyone with them can control your wallet."
    private static let setupErrorTitles = ["Wallet Setup Unavailable", "Too Many Requests", "Couldn't Connect",
                                           "Couldn't Save API Key", "Couldn't Load Provider", "Couldn't Change Provider"]

    private enum Error: Swift.Error { case missingConfiguration, missingRecoveryWords }

    let driver: UITestApp

    var createWalletButton: XCUIElement { driver.app.buttons["Create Wallet"] }
    var importWalletButton: XCUIElement { driver.app.buttons["Import Wallet"] }
    var continueButton: XCUIElement { driver.app.buttons["Continue"] }
    var backButton: XCUIElement { driver.app.buttons["BackButton"] }
    var backupConfirmation: XCUIElement { driver.app.alerts["Have you saved your recovery words?"] }
    var recoveryWords: XCUIElement { driver.app.secureTextFields["Recovery words"] }
    var revealedRecoveryWords: XCUIElement {
        driver.app.textFields.matching(NSPredicate(format: "value == %@", Self.phrase)).firstMatch
    }
    var showWordsButton: XCUIElement { driver.app.buttons["Show words"] }
    var hideWordsButton: XCUIElement { driver.app.buttons["Hide words"] }
    var invalidRecoveryError: XCUIElement {
        driver.app.staticTexts["These words don't form a valid recovery phrase. Check their spelling and order."]
    }
    var passphrase: XCUIElement { driver.app.secureTextFields["BIP-39 passphrase, optional"] }
    var revealedPassphrase: XCUIElement { driver.app.textFields["BIP-39 passphrase, optional"] }
    var showPassphraseButton: XCUIElement { driver.app.buttons["Show passphrase"] }
    var hidePassphraseButton: XCUIElement { driver.app.buttons["Hide passphrase"] }
    var solanaProvider: XCUIElement { driver.app.buttons["Solana"] }
    var recoveryWordsAreEmpty: Bool { recoveryWords.value as? String == "Recovery words" }
    var passphraseIsEmpty: Bool { (passphrase.value as? String ?? "Optional") == "Optional" }
    private var keySheet: XCUIElement { driver.app.navigationBars["Connect to Helius"] }

    func expectWelcome() throws {
        try driver.waitFor(createWalletButton)
    }

    func expectWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(driver.portfolioTab, label: "Portfolio", file: file, line: line)
    }

    func expectRPC(file: StaticString = #filePath, line: UInt = #line) throws {
        try expectSetupOutcome(driver.app.navigationBars["RPC"], label: "RPC", file: file, line: line)
        try driver.waitFor(driver.app.staticTexts["Step 2 of 2"], file: file, line: line)
        try driver.waitForAbsence(backButton, file: file, line: line)
    }

    func expectRecovery() throws {
        try driver.waitFor(driver.app.navigationBars["Recovery Phrase"])
        try driver.waitFor(driver.app.staticTexts["Step 1 of 2"])
        try driver.waitFor(driver.app.staticTexts[Self.recoveryGuidance])
        let lastWord = driver.app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"12\. [a-z]+"#))
        try driver.waitFor(lastWord.firstMatch)
        let words = driver.app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"([1-9]|1[0-2])\. [a-z]+"#))
        guard words.count == 12 else {
            XCTFail("Recovery must expose twelve numbered word labels")
            throw Error.missingRecoveryWords
        }
    }

    func expectKeyRejected(file: StaticString = #filePath, line: UInt = #line) throws {
        let message = "Your provider didn't accept this API key. Check it and try again."
        try expectSetupOutcome(driver.app.staticTexts[message], label: message, file: file, line: line)
    }

    func reachBackupConfirmation() throws {
        try driver.tap(createWalletButton)
        try expectRecovery()
        try driver.tap(continueButton)
        try driver.waitFor(backupConfirmation)
    }

    func answerBackupConfirmation(saved: Bool) throws {
        try driver.tap(backupConfirmation.buttons[saved ? "Yes" : "No"])
    }

    func createWallet() throws {
        try reachBackupConfirmation()
        try answerBackupConfirmation(saved: true)
        try expectRPC()
        try driver.waitForAbsence(driver.app.staticTexts[Self.recoveryGuidance])
    }

    func openImport() throws {
        try driver.tap(importWalletButton)
        try driver.waitFor(recoveryWords)
        try driver.waitFor(driver.app.staticTexts["Step 1 of 2"])
    }

    func enterPhrase(_ phrase: String = Self.phrase) throws {
        try driver.type(phrase + "\n", into: recoveryWords)
    }

    func enterPassphrase(_ passphrase: String) throws {
        let field = self.passphrase
        driver.reveal(field, swiping: .up)
        try driver.type(passphrase + "\n", into: field)
    }

    func chooseHelius(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Helius"], file: file, line: line)
        try expectSetupOutcome(keySheet, label: "Connect to Helius", file: file, line: line)
    }

    func hittableContinueButton(file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try driver.frontButton("Continue", file: file, line: line)
    }

    func submitProviderKey(_ key: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let field = driver.app.secureTextFields["RPC API key"]
        try driver.type(key, into: field, file: file, line: line)
        try driver.tap(try hittableContinueButton(file: file, line: line), file: file, line: line)
    }

    @discardableResult
    func openWallet(file: StaticString = #filePath, line: UInt = #line) throws -> PortfolioPage {
        try driver.tap(continueButton, file: file, line: line)
        return try showPortfolio(file: file, line: line)
    }

    @discardableResult
    func connectProvider(file: StaticString = #filePath, line: UInt = #line) throws -> PortfolioPage {
        guard let key = ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
              !key.isEmpty, !key.hasPrefix("$(") else {
            XCTFail("HELIUS_API_KEY must be configured for UI tests", file: file, line: line)
            throw Error.missingConfiguration
        }
        try chooseHelius(file: file, line: line)
        try submitProviderKey(key, file: file, line: line)
        return try showPortfolio(file: file, line: line)
    }

    private func showPortfolio(file: StaticString, line: UInt) throws -> PortfolioPage {
        try expectWallet(file: file, line: line)
        let portfolio = PortfolioPage(driver: driver)
        try portfolio.open(file: file, line: line)
        return portfolio
    }

    private func expectSetupOutcome(_ destination: XCUIElement, label: String,
                                    file: StaticString, line: UInt) throws {
        try driver.expectOutcome(destination, matching: NSPredicate(format: "label == %@", label),
                                 unless: Self.setupErrorTitles, file: file, line: line)
    }
}
