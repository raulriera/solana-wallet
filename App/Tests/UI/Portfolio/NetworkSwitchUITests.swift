import XCTest

@MainActor
final class NetworkSwitchUITests: XCTestCase {
    @objc(testSwitchingTheNetworkReturnsThePortfolioToItsTokenListAndReturnError:)
    func `test Switching the network returns the portfolio to its token list`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch(with: .newWallet)
        let portfolio = PortfolioPage(driver: app)

        try app.tap(portfolio.holding("SOL"))
        let details = portfolio.tokenDetails("Solana")
        try app.waitFor(details)

        try SettingsPage(driver: app).switchNetwork(to: "Devnet")
        try portfolio.open()

        try app.waitFor(portfolio.addTokenButton)
        try app.waitForAbsence(details)
        try app.waitFor(portfolio.holding("SOL"))
    }
}
