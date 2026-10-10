import UIKit
import XCTest

/// Adds a public token to a disposable wallet's portfolio by pasting its mint address.
@MainActor
final class TokenAdditionUITests: XCTestCase {
    /// BONK's mainnet mint address, a public token with an on-chain name.
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    /// The title of the alert that reports a failed lookup or add.
    private static let errorTitle = "Couldn't Add Token"

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
        try flow.expectOutcome(flow.app.staticTexts["Bonk · Solana"], matching: preview, unless: [Self.errorTitle])
        // The toolbar's Add Token button stays behind the sheet and can't be tapped, so tap the sheet's own button.
        let addButtons = flow.app.buttons.matching(identifier: "Add Token").allElementsBoundByIndex
        try flow.tap(try XCTUnwrap(addButtons.first(where: \.isHittable)))

        let listed = NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@",
                                 XCUIElement.ElementType.button.rawValue, "Bonk")
        try flow.expectOutcome(flow.app.buttons.matching(listed).firstMatch, matching: listed, unless: [Self.errorTitle])
        try flow.waitForAbsence(paste)
    }
}
