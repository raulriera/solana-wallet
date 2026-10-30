import XCTest

@MainActor
final class RecoveryPhraseUITests: XCTestCase {
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

        try flow.openSecurity()
        try flow.tap(flow.app.buttons["Show Recovery Phrase"])

        try flow.waitFor(flow.app.navigationBars["Recovery Phrase"])
        for (position, word) in zip(1..., OnboardingApp.phrase.split(separator: " ")) {
            try flow.waitFor(flow.app.staticTexts["\(position). \(word)"])
        }
        let path = element(containing: "m/44'/501'/", in: flow.app)
        if !path.exists { flow.app.swipeUp() }
        try flow.waitFor(element(containing: "TrEzOr", in: flow.app))
        try flow.waitFor(path)
    }

    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        ).firstMatch
    }
}
