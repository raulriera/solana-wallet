import XCTest

@MainActor
struct ContactsPage {
    let driver: UITestApp

    var noContacts: XCUIElement { driver.app.staticTexts["No Contacts"] }
    var newPaymentTitle: XCUIElement { driver.app.staticTexts["New Payment"] }
    var newPaymentButton: XCUIElement { driver.app.buttons["New Payment"].firstMatch }

    func contact(_ name: String) -> XCUIElement {
        driver.app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func open(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.contactsTab, file: file, line: line)
    }

    func startPayment(to address: String, shownAs shortAddress: String, named name: String? = nil,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(newPaymentButton, file: file, line: line)
        try driver.paste(address)
        if let name {
            try driver.type(name, into: driver.app.textFields["Name (Optional)"], file: file, line: line)
        }
        try driver.tap(try driver.frontButton("Continue", file: file, line: line), file: file, line: line)
        try driver.waitFor(driver.app.navigationBars[name ?? shortAddress], file: file, line: line)
    }

    @discardableResult
    func showSidebar(file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let back = driver.app.navigationBars.buttons["BackButton"]
        if back.exists {
            try driver.tap(back, file: file, line: line)
            return true
        }
        let showSidebar = driver.app.buttons["Show Sidebar"]
        if showSidebar.exists { try driver.tap(showSidebar, file: file, line: line) }
        return false
    }

    func addContact(named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Details"], file: file, line: line)
        try driver.tap(driver.app.buttons["Add Contact"], file: file, line: line)
        try driver.type(name, into: driver.app.textFields["Name"], file: file, line: line)
        try driver.tap(try driver.frontButton("Save Contact", file: file, line: line), file: file, line: line)
        try driver.waitFor(driver.app.navigationBars[name], file: file, line: line)
    }

    func deleteContact(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Delete Contact"], file: file, line: line)
        try driver.tap(try driver.frontButton("Delete Contact", file: file, line: line), file: file, line: line)
    }
}
