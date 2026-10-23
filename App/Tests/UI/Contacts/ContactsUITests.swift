import XCTest

/// Pays and saves a new wallet's first recipients from Contacts, which starts and ends on one full-width empty screen.
///
/// The simulator can share its clipboard with the Mac, so each run leaves the pasted address on it.
@MainActor
final class ContactsUITests: XCTestCase {
    /// A public address that no new wallet has saved or paid.
    private static let address = "5Wqz5yrwY2mGG9qqD9MUU7QYehEkv8kcdQgMKhV7wXaV"
    /// The address as the keypad and details title it while it isn't saved.
    private static let shortAddress = "5Wqz…wXaV"

    /// An unnamed payment's address isn't saved: with the sidebar beside the keypad it's listed only under New Payment
    /// while selected, and going back from the keypad on iPhone leaves Contacts empty again. A named one is saved and
    /// listed under Contacts.
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
        // The row reads its name, then its short address.
        let row = NSPredicate(format: "label BEGINSWITH %@", "Alice")
        try flow.waitFor(flow.app.descendants(matching: .any).matching(row).firstMatch)
        // The address now has a contact's row, so it no longer needs its own.
        try flow.waitForAbsence(newPayment)
        XCTAssertFalse(flow.app.staticTexts["No Contacts"].exists, "Contacts stayed empty after naming a recipient.")
    }

    /// Saving the paid address from its details names the keypad's recipient; deleting that only contact asks first,
    /// then returns to the empty screen.
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

    /// Creates a disposable wallet on the public provider and opens its empty Contacts tab.
    /// - Returns: The app's flow, showing the empty Contacts tab.
    /// - Throws: A missing or unavailable control, or an explicit wallet setup failure.
    private func openContacts() throws -> OnboardingApp {
        let flow = OnboardingApp()
        try flow.launch()
        try flow.createWallet()
        try flow.openWallet()
        // The Contacts tab, in the bottom tab bar on iPhone and the top one on iPad, which isn't a tab bar element.
        try flow.tap(flow.app.buttons["Contacts"].firstMatch)
        try flow.waitFor(flow.app.staticTexts["No Contacts"])
        return flow
    }

    /// Pastes the address into a new payment, names it when asked, and waits for the keypad.
    /// - Parameters:
    ///   - flow: The app's flow, showing Contacts.
    ///   - name: The recipient's name, which saves them as a contact, or `nil` to leave the address unsaved.
    /// - Throws: A missing or unavailable control.
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

    /// Goes back from the keypad to the sidebar when the split view shows one column, as on iPhone, and otherwise
    /// shows the sidebar that a new payment hides.
    /// - Parameter flow: The app's flow, showing the keypad.
    /// - Returns: `true` when it went back; `false` when the sidebar shows beside or over the keypad.
    /// - Throws: A back or sidebar button that can't be tapped.
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
