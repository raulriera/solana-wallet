import XCTest

@MainActor
final class ResetAppUITests: XCTestCase {
    @objc(testResetAppReturnsToWelcomeAndReturnError:)
    func `test Reset App in Settings returns the window to Welcome`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        try flow.openWallet()

        try flow.openSecurity()
        try flow.tap(flow.app.collectionViews.buttons["Reset App"])
        try flow.tap(flow.app.buttons["Continue"])
        try flow.tap(flow.app.collectionViews.buttons["Reset App"])
        let confirmation = flow.app.alerts["Reset App?"]
        try flow.waitFor(confirmation)
        try flow.tap(confirmation.buttons["Reset App"])

        try flow.expectWelcome()
    }
}
