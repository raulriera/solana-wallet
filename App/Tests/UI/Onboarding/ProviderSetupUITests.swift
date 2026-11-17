import XCTest

@MainActor
final class ProviderSetupUITests: XCTestCase {
    @objc(testContinueOpensTheWalletOnSolanaAndReturnError:)
    func `test Continue opens the wallet on Solana's public RPC without a key`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.createWallet()
        XCTAssertTrue(onboarding.solanaProvider.isSelected)

        let portfolio = try onboarding.openWallet()

        try app.waitFor(portfolio.holding("SOL"))
    }

    @objc(testRejectedKeyStaysReadyToRetryAndReturnError:)
    func `test A rejected key shows an inline error and stays ready to retry`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.createWallet()
        try onboarding.chooseHelius()
        XCTAssertFalse(try onboarding.hittableContinueButton().isEnabled)

        try onboarding.submitProviderKey("00000000-0000-0000-0000-000000000000")

        try onboarding.expectKeyRejected()
        XCTAssertTrue(try onboarding.hittableContinueButton().isEnabled)
    }
}
