import XCTest

@MainActor
final class TokenAdditionUITests: XCTestCase {
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    private static let additionErrorTitle = "Couldn't Add Token"

    @objc(testAddingATokenByItsMintAddressListsItUntilItIsRemovedAndReturnError:)
    func `test Adding a token by its mint address lists it until it is removed`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        try flow.connectProvider()

        try flow.tap(flow.app.navigationBars.buttons["Add Token"])
        try flow.paste(Self.bonk)
        let preview = NSPredicate(format: "label == %@", "Bonk · Solana")
        try flow.expectOutcome(flow.app.staticTexts["Bonk · Solana"], matching: preview,
                               unless: [Self.additionErrorTitle])
        try flow.tap(try flow.frontButton("Add Token"))

        let listed = OnboardingApp.holdingLabel(beginningWith: "Bonk")
        let token = flow.holding("Bonk")
        try flow.expectOutcome(token, matching: listed, unless: [Self.additionErrorTitle])
        try flow.waitForAbsence(flow.app.buttons["Paste"])

        try flow.tap(token)
        try flow.tap(flow.app.buttons["More"])
        try flow.tap(flow.app.buttons["Remove Token"])
        let confirmation = flow.app.alerts["Remove Bonk?"]
        try flow.waitFor(confirmation)
        try flow.tap(confirmation.buttons["Remove"])
        try flow.waitForAbsence(token)

        flow.relaunch()
        try flow.showPortfolio()
        try flow.waitFor(flow.holding("SOL"))
        XCTAssertFalse(token.exists, "The removed token came back after a relaunch.")
    }
}
