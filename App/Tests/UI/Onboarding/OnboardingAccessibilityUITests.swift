import XCTest

/// Audits the production onboarding screens without suppressing accessibility issues.
@MainActor
final class OnboardingAccessibilityUITests: XCTestCase {
    /// Welcome exposes readable content and accessible native setup actions.
    @objc(testWelcomeAccessibilityAndReturnError:)
    func `test Welcome passes the accessibility audit`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()

        try flow.app.performAccessibilityAudit()
    }

    /// Phrase entry and its guidance remain accessible before any recovery is supplied.
    @objc(testImportAccessibilityAndReturnError:)
    func `test Import passes the accessibility audit`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.openImport()

        try flow.app.performAccessibilityAudit()
        let passphrase = flow.app.secureTextFields["BIP-39 passphrase, optional"]
        if !passphrase.isHittable { flow.app.swipeUp() }
        try flow.waitFor(passphrase)
        try flow.app.performAccessibilityAudit()
    }

    /// Disposable generated recovery exposes its numbered words and backup action accessibly.
    @objc(testRecoveryAccessibilityAndReturnError:)
    func `test Recovery phrase passes the accessibility audit`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.tap(flow.app.buttons["Create Wallet"])
        try flow.expectRecovery()

        try flow.app.performAccessibilityAudit()
    }

    /// The key field, its guidance, and the Helius link remain accessible after a wallet is saved.
    @objc(testProviderSetupAccessibilityAndReturnError:)
    func `test Provider setup passes the accessibility audit`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()

        try flow.app.performAccessibilityAudit()
    }
}
