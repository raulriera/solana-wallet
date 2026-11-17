import XCTest

@MainActor
final class TokenAdditionUITests: XCTestCase {
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

    @objc(testAddingATokenByItsMintAddressListsItUntilItIsRemovedAndReturnError:)
    func `test Adding a token by its mint address lists it until it is removed`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.createWallet()
        let portfolio = try onboarding.connectProvider()

        try portfolio.addToken(Self.bonk, previewing: "Bonk · Solana")

        let token = try portfolio.expectAddedToken("Bonk")
        try app.waitForAbsence(portfolio.pasteButton)

        try portfolio.removeToken(token, named: "Bonk")
        try app.waitForAbsence(token)

        app.relaunch()
        try onboarding.expectWallet()
        try portfolio.open()
        try app.waitFor(portfolio.holding("SOL"))
        XCTAssertFalse(token.exists, "The removed token came back after a relaunch.")
    }
}
