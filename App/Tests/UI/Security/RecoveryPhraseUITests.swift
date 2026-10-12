import XCTest

/// Exercises the Settings backup of an imported public fixture through XCUIApplication.
@MainActor
final class RecoveryPhraseUITests: XCTestCase {
    /// Settings shows the same words, the original passphrase, and an account path after import.
    @objc(testShowRecoveryPhraseAfterImportAndReturnError:)
    func `test Security & Privacy shows the imported words, passphrase, and account path`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()
        try flow.enterPhrase()
        try flow.enterPassphrase(" TrEzOr ")
        try flow.tap(flow.submitImport)
        try flow.expectProviders()
        try flow.openWallet()

        try flow.tap(flow.settingsTab)
        try flow.tap(flow.app.buttons["Security & Privacy"])
        try flow.tap(flow.app.buttons["Show Recovery Phrase"])

        try flow.waitFor(flow.app.navigationBars["Recovery Phrase"])
        for (position, word) in zip(1..., OnboardingApp.phrase.split(separator: " ")) {
            try flow.waitFor(flow.app.staticTexts["\(position). \(word)"])
        }
        // The form builds rows only as they scroll into view, and the account path sits below the words.
        let path = element(containing: "m/44'/501'/", in: flow.app)
        if !path.exists { flow.app.swipeUp() }
        try flow.waitFor(element(containing: "TrEzOr", in: flow.app))
        try flow.waitFor(path)
    }

    /// Finds text shown as either an element's label or its value, as in labeled rows.
    /// - Parameters:
    ///   - text: The expected visible text.
    ///   - app: The running app.
    /// - Returns: The first element whose label or value contains the text.
    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        ).firstMatch
    }
}
