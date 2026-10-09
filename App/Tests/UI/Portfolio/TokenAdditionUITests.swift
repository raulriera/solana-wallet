import UIKit
import XCTest

/// Adds a public token to a disposable wallet's portfolio by pasting its mint address.
@MainActor
final class TokenAdditionUITests: XCTestCase {
    /// BONK's mainnet mint address, a public token with an on-chain name.
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    /// The title of the alert that reports a failed lookup or add.
    private static let failure = "Couldn't Add Token"

    /// The pasted address previews the token before it can be added; adding it closes the sheet and lists the token.
    ///
    /// The simulator can share its clipboard with the Mac, so the run leaves BONK's address on it.
    @objc(testAddingATokenByItsMintAddressListsItAndReturnError:)
    func `test Adding a token by its mint address lists it`() throws {
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
        try flow.expectOutcome(flow.app.staticTexts["Bonk · Solana"], matching: preview, unless: Self.failure)
        // The toolbar's Add Token button stays behind the sheet, so the sheet's own button comes last.
        let addButtons = flow.app.buttons.matching(identifier: "Add Token")
        try flow.tap(addButtons.element(boundBy: addButtons.count - 1))

        let listed = NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@",
                                 XCUIElement.ElementType.button.rawValue, "Bonk")
        try flow.expectOutcome(flow.app.buttons.matching(listed).firstMatch, matching: listed, unless: Self.failure)
        try flow.waitForAbsence(paste)
    }
}
