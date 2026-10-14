import XCTest

/// Switches a disposable wallet's window to Devnet while the portfolio shows a token's details.
@MainActor
final class NetworkSwitchUITests: XCTestCase {
    /// Devnet has its own tokens, so a switch returns the portfolio from mainnet SOL's details to devnet's token list,
    /// although SOL is on both networks.
    @objc(testSwitchingTheNetworkReturnsThePortfolioToItsTokenListAndReturnError:)
    func `test Switching the network returns the portfolio to its token list`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        try flow.openWallet()

        try flow.tap(flow.holding("SOL"))
        let details = flow.app.navigationBars["Solana"]
        try flow.waitFor(details)

        try flow.tap(flow.settingsTab)
        try flow.tap(flow.app.buttons["Network"])
        try flow.tap(flow.app.buttons["Devnet"])
        let chosen = NSPredicate(format: "label == %@ AND selected == true", "Devnet")
        try flow.waitFor(flow.app.buttons.matching(chosen).firstMatch)
        try flow.tap(flow.portfolioTab)

        // Only the token list has Add Token; a token's details have the More menu instead.
        try flow.waitFor(flow.app.navigationBars.buttons["Add Token"])
        try flow.waitForAbsence(details)
        try flow.waitFor(flow.holding("SOL"))
    }
}
