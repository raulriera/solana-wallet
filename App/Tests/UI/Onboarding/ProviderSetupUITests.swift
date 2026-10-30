import XCTest

@MainActor
final class ProviderSetupUITests: XCTestCase {
    @objc(testContinueOpensTheWalletOnSolanaAndReturnError:)
    func `test Continue opens the wallet on Solana's public RPC without a key`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        XCTAssertTrue(flow.app.buttons["Solana"].isSelected)

        try flow.openWallet()

        try flow.waitFor(flow.holding("SOL"))
    }

    @objc(testRejectedKeyStaysReadyToRetryAndReturnError:)
    func `test A rejected key shows an inline error and stays ready to retry`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        try flow.chooseHelius()
        XCTAssertFalse(try flow.frontButton("Continue").isEnabled)

        try flow.submitProviderKey("00000000-0000-0000-0000-000000000000")

        try flow.expectKeyRejected()
        XCTAssertTrue(try flow.frontButton("Continue").isEnabled)
    }
}
