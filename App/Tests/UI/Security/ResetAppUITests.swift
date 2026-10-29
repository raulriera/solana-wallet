import XCTest

/// Exercises Reset App in Settings with a disposable, unfunded wallet through XCUIApplication.
@MainActor
final class ResetAppUITests: XCTestCase {
    /// Resetting from Settings removes the wallet while its tab is on screen, and the window returns to Welcome.
    @objc(testResetAppReturnsToWelcomeAndReturnError:)
    func `test Reset App in Settings returns the window to Welcome`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        try flow.openWallet()

        try flow.openSecurity()
        // The Form's button, not a back button that the next screen titles with Reset App.
        try flow.tap(flow.app.collectionViews.buttons["Reset App"])
        try flow.tap(flow.app.buttons["Continue"])
        try flow.tap(flow.app.collectionViews.buttons["Reset App"])
        let confirmation = flow.app.alerts["Reset App?"]
        try flow.waitFor(confirmation)
        try flow.tap(confirmation.buttons["Reset App"])

        try flow.expectWelcome()
    }
}
