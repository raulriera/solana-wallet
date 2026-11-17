import XCTest

@MainActor
final class ResetAppUITests: XCTestCase {
    @objc(testResetAppReturnsToWelcomeAndReturnError:)
    func `test Reset App in Settings returns the window to Welcome`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.createWallet()
        try onboarding.openWallet()

        try SettingsPage(driver: app).openSecurity().resetApp()

        try onboarding.expectWelcome()
    }
}
