import XCTest

@MainActor
final class ResetAppUITests: XCTestCase {
    @objc(testResetAppReturnsToWelcomeAndReturnError:)
    func `test Reset App in Settings returns the window to Welcome`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch(with: .newWallet)

        try SettingsPage(driver: app).openSecurity().resetApp()

        try OnboardingPage(driver: app).expectWelcome()
    }
}
