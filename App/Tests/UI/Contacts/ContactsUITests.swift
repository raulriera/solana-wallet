import XCTest

@MainActor
final class ContactsUITests: XCTestCase {
    private static let address = "5Wqz5yrwY2mGG9qqD9MUU7QYehEkv8kcdQgMKhV7wXaV"
    private static let shortAddress = "5Wqz…wXaV"

    @objc(testANewWalletsContactsStayEmptyUntilARecipientIsNamedAndReturnError:)
    func `test A new wallet's contacts stay empty until a recipient is named`() throws {
        let flow = try openContacts()
        defer { flow.app.terminate() }
        let newPayment = flow.app.staticTexts["New Payment"]

        try startPayment(in: flow, name: nil)
        if try showSidebar(in: flow) {
            try flow.waitFor(flow.app.staticTexts["No Contacts"])
        } else {
            try flow.waitFor(newPayment)
        }

        try startPayment(in: flow, name: "Alice")
        try showSidebar(in: flow)
        let row = NSPredicate(format: "label BEGINSWITH %@", "Alice")
        try flow.waitFor(flow.app.descendants(matching: .any).matching(row).firstMatch)
        try flow.waitForAbsence(newPayment)
        XCTAssertFalse(flow.app.staticTexts["No Contacts"].exists, "Contacts stayed empty after naming a recipient.")
    }

    @objc(testDeletingTheOnlyContactReturnsToTheEmptyContactsAndReturnError:)
    func `test Deleting the only contact returns to the empty contacts`() throws {
        let flow = try openContacts()
        defer { flow.app.terminate() }

        try startPayment(in: flow, name: nil)
        try flow.tap(flow.app.buttons["Details"])
        try flow.tap(flow.app.buttons["Add Contact"])
        let name = flow.app.textFields["Name"]
        try flow.tap(name)
        name.typeText("Alice")
        try flow.tap(try flow.frontButton("Save Contact"))
        try flow.waitFor(flow.app.navigationBars["Alice"])

        try flow.tap(flow.app.buttons["Delete Contact"])
        try flow.tap(try flow.frontButton("Delete Contact"))
        try flow.waitFor(flow.app.staticTexts["No Contacts"])
        try flow.waitFor(flow.app.buttons["New Payment"])
    }

    private func openContacts() throws -> OnboardingApp {
        let flow = OnboardingApp()
        try flow.launch()
        try flow.createWallet()
        try flow.openWallet()
        try flow.tap(flow.app.buttons["Contacts"].firstMatch)
        try flow.waitFor(flow.app.staticTexts["No Contacts"])
        return flow
    }

    private func startPayment(in flow: OnboardingApp, name: String?) throws {
        try flow.tap(flow.app.buttons["New Payment"].firstMatch)
        try flow.paste(Self.address)
        if let name {
            let field = flow.app.textFields["Name (Optional)"]
            try flow.tap(field)
            field.typeText(name)
        }
        try flow.tap(try flow.frontButton("Continue"))
        try flow.waitFor(flow.app.navigationBars[name ?? Self.shortAddress])
    }

    @discardableResult
    private func showSidebar(in flow: OnboardingApp) throws -> Bool {
        let back = flow.app.navigationBars.buttons["BackButton"]
        if back.exists {
            try flow.tap(back)
            return true
        }
        let showSidebar = flow.app.buttons["Show Sidebar"]
        if showSidebar.exists { try flow.tap(showSidebar) }
        return false
    }
}
