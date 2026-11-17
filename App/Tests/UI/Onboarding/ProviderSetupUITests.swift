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
        let rpc = RPCPage(driver: app)
        try rpc.chooseHelius()
        XCTAssertFalse(try rpc.hittableContinueButton().isEnabled)

        try rpc.submitKey("00000000-0000-0000-0000-000000000000")

        try rpc.expectKeyRejected()
        XCTAssertTrue(try rpc.hittableContinueButton().isEnabled)
    }
}
