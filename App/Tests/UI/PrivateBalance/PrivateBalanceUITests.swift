import XCTest

@MainActor
final class PrivateBalanceUITests: XCTestCase {
    @objc(testMakingSOLPrivateShowsItPendingAndReturnError:)
    func `test Making SOL private shows it pending`() throws {
        let (app, privateBalance) = try openPrivateBalance()
        defer { app.terminate() }

        try privateBalance.startMove("Make SOL Private")
        try PaymentsPage(driver: app).enterAmount("0.001")
        try privateBalance.review()
        try privateBalance.approve("Make SOL Private")

        try privateBalance.expectResult("0.001 SOL is pending.")
    }

    @objc(testMakingSOLPublicMovesItToThePublicBalanceAndReturnError:)
    func `test Making SOL public moves it to the public balance`() throws {
        let (app, privateBalance) = try openPrivateBalance()
        defer { app.terminate() }

        try privateBalance.startMove("Make SOL Public")
        try PaymentsPage(driver: app).enterAmount("0.001")
        try privateBalance.review()
        try privateBalance.approve("Make SOL Public")

        try privateBalance.expectResult("0.001 SOL is in your public balance.")
    }

    @objc(testSendingSOLPrivatelyPutsItInTheRecipientsPrivateBalanceAndReturnError:)
    func `test Sending SOL privately puts it in the recipient's private balance`() throws {
        let (app, privateBalance) = try openPrivateBalance()
        defer { app.terminate() }

        try privateBalance.startMove("Send Privately")
        try app.tap(ContactsPage(driver: app).contact("Account 2"))
        try PaymentsPage(driver: app).enterAmount("0.001")
        try privateBalance.review()
        try privateBalance.approve("Send SOL Privately")

        try privateBalance.expectResult("0.001 SOL is in Account 2's private balance.")
    }

    private func openPrivateBalance() throws -> (UITestApp, PrivateBalancePage) {
        let app = UITestApp()
        app.launch(with: .devWallet)
        let settings = SettingsPage(driver: app)
        try settings.switchNetwork(to: "Devnet")
        try settings.openAccounts().chooseFirstAccount()
        try settings.useHelius(key: ProcessInfo.processInfo.environment["HELIUS_API_KEY"]!)
        let portfolio = PortfolioPage(driver: app)
        try portfolio.open()
        try app.tap(portfolio.holding("SOL"))
        try app.waitFor(portfolio.tokenDetails("Solana"))
        let privateBalance = PrivateBalancePage(driver: app)
        try privateBalance.turnOn()
        return (app, privateBalance)
    }
}
