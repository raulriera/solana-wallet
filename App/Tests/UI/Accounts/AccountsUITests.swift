import XCTest

@MainActor
final class AccountsUITests: XCTestCase {
    private static let errorTitles = ["Couldn't Add Account", "Couldn't Rename Account", "Couldn't Delete Account"]

    @objc(testAddAccountSavesTheWalletsNextAccountAndReturnError:)
    func `test Add Account saves the wallet's next account`() throws {
        let flow = try openAccounts()
        defer { flow.app.terminate() }

        try flow.tap(flow.app.buttons["Add Account"])

        try flow.expectOutcome(row("Account 2", in: flow), matching: Self.rowLabel(beginningWith: "Account 2"),
                               unless: Self.errorTitles)
        try flow.waitFor(row("Account 1", in: flow))
        flow.relaunch()
        try showAccounts(in: flow)
        try flow.waitFor(row("Account 2", in: flow))
    }

    @objc(testChoosingAnAccountChecksItAndReturnError:)
    func `test Choosing an account checks it`() throws {
        let flow = try openAccounts()
        defer { flow.app.terminate() }
        try flow.tap(flow.app.buttons["Add Account"])
        try flow.expectOutcome(row("Account 2", in: flow), matching: Self.rowLabel(beginningWith: "Account 2"),
                               unless: Self.errorTitles)

        try flow.tap(row("Account 2", in: flow))

        XCTAssertTrue(row("Account 2", in: flow).isSelected, "The chosen account isn't checked.")
        XCTAssertFalse(row("Account 1", in: flow).isSelected, "The first account is still checked.")
    }

    @objc(testANewNameRenamesTheAccountAndReturnError:)
    func `test A new name renames the account`() throws {
        let flow = try openAccounts()
        defer { flow.app.terminate() }

        try flow.tap(info("Account 1", in: flow))
        let name = flow.app.textFields["Name"]
        try flow.tap(name)
        name.typeText("Savings")
        try flow.tap(try flow.frontButton("Save Name"))

        try flow.expectOutcome(row("Savings", in: flow), matching: Self.rowLabel(beginningWith: "Savings"),
                               unless: Self.errorTitles)
        try flow.waitForAbsence(row("Account 1", in: flow))
        flow.relaunch()
        try showAccounts(in: flow)
        try flow.waitFor(row("Savings", in: flow))
    }

    @objc(testDeletingAnAddedAccountRemovesItAndReturnError:)
    func `test Deleting an added account removes it`() throws {
        let flow = try openAccounts()
        defer { flow.app.terminate() }
        try flow.tap(flow.app.buttons["Add Account"])
        try flow.expectOutcome(row("Account 2", in: flow), matching: Self.rowLabel(beginningWith: "Account 2"),
                               unless: Self.errorTitles)

        try flow.tap(info("Account 2", in: flow))
        try flow.tap(flow.app.buttons["Delete Account"])
        try flow.tap(try flow.frontButton("Delete Account"))

        try flow.waitForAbsence(row("Account 2", in: flow))
        try flow.waitFor(row("Account 1", in: flow))
        XCTAssertFalse(flow.app.alerts["Couldn't Delete Account"].exists, "The app reported a failed deletion.")
        try flow.tap(info("Account 1", in: flow))
        try flow.waitFor(flow.app.textFields["Name"])
        XCTAssertFalse(flow.app.buttons["Delete Account"].exists, "The window's own account offered a deletion.")
        flow.relaunch()
        try showAccounts(in: flow)
        try flow.waitFor(row("Account 1", in: flow))
        XCTAssertFalse(row("Account 2", in: flow).exists, "The deleted account came back after a relaunch.")
    }

    private func openAccounts() throws -> OnboardingApp {
        let flow = OnboardingApp()
        try flow.launch()
        try flow.createWallet()
        try flow.openWallet()
        try showAccounts(in: flow)
        return flow
    }

    private func showAccounts(in flow: OnboardingApp) throws {
        try flow.expectWallet()
        try flow.tap(flow.settingsTab)
        try flow.tap(flow.app.buttons["Accounts"])
        try flow.waitFor(flow.app.navigationBars["Accounts"])
    }

    private func row(_ name: String, in flow: OnboardingApp) -> XCUIElement {
        flow.app.buttons.matching(Self.rowLabel(beginningWith: name)).firstMatch
    }

    private func info(_ name: String, in flow: OnboardingApp) -> XCUIElement {
        flow.app.cells.containing(Self.rowLabel(beginningWith: name)).buttons["More Info"].firstMatch
    }

    private static func rowLabel(beginningWith name: String) -> NSPredicate {
        NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@", XCUIElement.ElementType.button.rawValue,
                    name + ",")
    }
}
