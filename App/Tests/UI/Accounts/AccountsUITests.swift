import XCTest

@MainActor
final class AccountsUITests: XCTestCase {
    @objc(testAddAccountSavesTheWalletsNextAccountAndReturnError:)
    func `test Add Account saves the wallet's next account`() throws {
        let (app, accounts) = try openAccounts()
        defer { app.terminate() }

        try app.tap(accounts.addAccountButton)

        try accounts.expectAccount("Account 2")
        try app.waitFor(accounts.row("Account 1"))
        app.relaunch()
        try showAccounts(in: app)
        try app.waitFor(accounts.row("Account 2"))
    }

    @objc(testChoosingAnAccountChecksItAndReturnError:)
    func `test Choosing an account checks it`() throws {
        let (app, accounts) = try openAccounts()
        defer { app.terminate() }
        try app.tap(accounts.addAccountButton)
        try accounts.expectAccount("Account 2")

        try app.tap(accounts.row("Account 2"))

        XCTAssertTrue(accounts.row("Account 2").isSelected, "The chosen account isn't checked.")
        XCTAssertFalse(accounts.row("Account 1").isSelected, "The first account is still checked.")
    }

    @objc(testANewNameRenamesTheAccountAndReturnError:)
    func `test A new name renames the account`() throws {
        let (app, accounts) = try openAccounts()
        defer { app.terminate() }

        try accounts.rename("Account 1", to: "Savings")

        try accounts.expectAccount("Savings")
        try app.waitForAbsence(accounts.row("Account 1"))
        app.relaunch()
        try showAccounts(in: app)
        try app.waitFor(accounts.row("Savings"))
    }

    @objc(testDeletingAnAddedAccountRemovesItAndReturnError:)
    func `test Deleting an added account removes it`() throws {
        let (app, accounts) = try openAccounts()
        defer { app.terminate() }
        try app.tap(accounts.addAccountButton)
        try accounts.expectAccount("Account 2")

        try accounts.deleteAccount("Account 2")

        try app.waitForAbsence(accounts.row("Account 2"))
        try app.waitFor(accounts.row("Account 1"))
        XCTAssertFalse(accounts.deletionError.exists, "The app reported a failed deletion.")
        try app.tap(accounts.infoButton(for: "Account 1"))
        try app.waitFor(accounts.nameField)
        XCTAssertFalse(accounts.deleteAccountButton.exists, "The window's own account offered a deletion.")
        app.relaunch()
        try showAccounts(in: app)
        try app.waitFor(accounts.row("Account 1"))
        XCTAssertFalse(accounts.row("Account 2").exists, "The deleted account came back after a relaunch.")
    }

    private func openAccounts() throws -> (UITestApp, AccountsPage) {
        let app = UITestApp()
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.createWallet()
        try onboarding.openWallet()
        return (app, try showAccounts(in: app))
    }

    @discardableResult
    private func showAccounts(in app: UITestApp) throws -> AccountsPage {
        try OnboardingPage(driver: app).expectWallet()
        return try SettingsPage(driver: app).openAccounts()
    }
}
