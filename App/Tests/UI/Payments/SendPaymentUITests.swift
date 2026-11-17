import XCTest

@MainActor
final class SendPaymentUITests: XCTestCase {
    @objc(testSendingSOLToAnotherAccountShowsItSentAndReturnError:)
    func `test Sending SOL to another account shows it sent`() throws {
        let app = UITestApp()
        defer { app.terminate() }
        app.launch(with: .devWallet)
        let settings = SettingsPage(driver: app)
        try settings.switchNetwork(to: "Devnet")
        try settings.openAccounts().chooseFirstAccount()
        let contacts = ContactsPage(driver: app)
        try contacts.open()
        try app.tap(contacts.contact("Account 2"))
        let payment = PaymentsPage(driver: app)

        try payment.enterAmount("0.001")
        try payment.review()
        try payment.send()

        try payment.expectSent("You sent 0.001 SOL to Account 2.")
    }
}
