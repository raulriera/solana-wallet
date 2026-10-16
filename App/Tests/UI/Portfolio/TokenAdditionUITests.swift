import UIKit
import XCTest

/// Adds a public token to a disposable wallet's portfolio by pasting its mint address, then removes it.
@MainActor
final class TokenAdditionUITests: XCTestCase {
    /// BONK's mainnet mint address, a public token with an on-chain name.
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    /// The title of the alert that reports a failed lookup or add.
    private static let additionErrorTitle = "Couldn't Add Token"

    /// The pasted address previews the token before it can be added; adding it closes the sheet and lists the token.
    /// Removing it from its details' More menu asks first, then takes it out of the list, also after a relaunch.
    ///
    /// The simulator can share its clipboard with the Mac, so the run leaves BONK's address on it.
    @objc(testAddingATokenByItsMintAddressListsItUntilItIsRemovedAndReturnError:)
    func `test Adding a token by its mint address lists it until it is removed`() throws {
        let flow = OnboardingApp()
        defer { flow.app.terminate() }
        try flow.launch()
        try flow.createWallet()
        try flow.connectProvider()

        UIPasteboard.general.string = Self.bonk
        try flow.tap(flow.app.navigationBars.buttons["Add Token"])
        let paste = flow.app.buttons["Paste"]
        try flow.tap(paste)
        let preview = NSPredicate(format: "label == %@", "Bonk · Solana")
        try flow.expectOutcome(flow.app.staticTexts["Bonk · Solana"], matching: preview,
                               unless: [Self.additionErrorTitle])
        // The toolbar's Add Token button stays behind the sheet and can't be tapped, so tap the sheet's own button.
        try flow.tap(try flow.frontButton("Add Token"))

        let listed = OnboardingApp.holdingLabel(beginningWith: "Bonk")
        let token = flow.holding("Bonk")
        try flow.expectOutcome(token, matching: listed, unless: [Self.additionErrorTitle])
        try flow.waitForAbsence(paste)

        try flow.tap(token)
        // The iPhone Duo shows the details' toolbar in a vertical bar outside the navigation bar.
        try flow.tap(flow.app.buttons["More"])
        try flow.tap(flow.app.buttons["Remove Token"])
        let confirmation = flow.app.alerts["Remove Bonk?"]
        try flow.waitFor(confirmation)
        try flow.tap(confirmation.buttons["Remove"])
        // The token leaves only once its list is saved; a failed save keeps it in the list.
        try flow.waitForAbsence(token)

        // A relaunch shows the saved list and cached balances, which no longer hold the token.
        flow.relaunch()
        try flow.showPortfolio()
        try flow.waitFor(flow.holding("SOL"))
        XCTAssertFalse(token.exists, "The removed token came back after a relaunch.")
    }
}
