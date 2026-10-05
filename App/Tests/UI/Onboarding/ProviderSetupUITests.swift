import XCTest

/// Exercises provider setup with a disposable wallet and a dummy key that Helius rejects.
@MainActor
final class ProviderSetupUITests: XCTestCase {
    /// Blank input can't be submitted; a rejected key shows an inline error and stays ready to retry.
    @objc(testRejectedKeyStaysReadyToRetryAndReturnError:)
    func `test A rejected key shows an inline error and stays ready to retry`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        XCTAssertFalse(flow.app.buttons["Continue"].isEnabled)

        try flow.submitProviderKey("00000000-0000-0000-0000-000000000000")

        try flow.expectKeyRejected()
        XCTAssertTrue(flow.app.buttons["Continue"].isEnabled)
    }
}
