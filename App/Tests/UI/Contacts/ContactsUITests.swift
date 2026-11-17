import XCTest

@MainActor
final class ContactsUITests: XCTestCase {
    private static let address = "5Wqz5yrwY2mGG9qqD9MUU7QYehEkv8kcdQgMKhV7wXaV"
    private static let shortAddress = "5Wqz…wXaV"

    @objc(testANewWalletsContactsStayEmptyUntilARecipientIsNamedAndReturnError:)
    func `test A new wallet's contacts stay empty until a recipient is named`() throws {
        let (app, contacts) = try openContacts()
        defer { app.terminate() }

        try contacts.startPayment(to: Self.address, shownAs: Self.shortAddress)
        if try contacts.showSidebar() {
            try app.waitFor(contacts.noContacts)
        } else {
            try app.waitFor(contacts.newPaymentTitle)
        }

        try contacts.startPayment(to: Self.address, shownAs: Self.shortAddress, named: "Alice")
        try contacts.showSidebar()
        try app.waitFor(contacts.contact("Alice"))
        try app.waitForAbsence(contacts.newPaymentTitle)
        XCTAssertFalse(contacts.noContacts.exists, "Contacts stayed empty after naming a recipient.")
    }

    @objc(testDeletingTheOnlyContactReturnsToTheEmptyContactsAndReturnError:)
    func `test Deleting the only contact returns to the empty contacts`() throws {
        let (app, contacts) = try openContacts()
        defer { app.terminate() }

        try contacts.startPayment(to: Self.address, shownAs: Self.shortAddress)
        try contacts.addContact(named: "Alice")

        try contacts.deleteContact()
        try app.waitFor(contacts.noContacts)
        try app.waitFor(contacts.newPaymentButton)
    }

    private func openContacts() throws -> (UITestApp, ContactsPage) {
        let app = UITestApp()
        app.launch()
        let onboarding = OnboardingPage(driver: app)
        try onboarding.expectWelcome()
        try onboarding.createWallet()
        try onboarding.openWallet()
        let contacts = ContactsPage(driver: app)
        try contacts.open()
        try app.waitFor(contacts.noContacts)
        return (app, contacts)
    }
}
