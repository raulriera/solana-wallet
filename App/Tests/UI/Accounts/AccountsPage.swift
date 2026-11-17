import XCTest

@MainActor
struct AccountsPage {
    private static let errorTitles = ["Couldn't Add Account", "Couldn't Rename Account", "Couldn't Delete Account"]

    let driver: UITestApp

    private static func rowPrefix(_ name: String) -> String {
        name + ","
    }

    var addAccountButton: XCUIElement { driver.app.buttons["Add Account"] }
    var nameField: XCUIElement { driver.app.textFields["Name"] }
    var deleteAccountButton: XCUIElement { driver.app.buttons["Delete Account"] }
    var deletionError: XCUIElement { driver.app.alerts["Couldn't Delete Account"] }

    func row(_ name: String) -> XCUIElement {
        driver.button(beginningWith: Self.rowPrefix(name))
    }

    func infoButton(for name: String) -> XCUIElement {
        driver.app.buttons["More Info About \(name)"].firstMatch
    }

    func expectShown(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.waitFor(driver.app.navigationBars["Accounts"], file: file, line: line)
    }

    func expectAccount(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.expectButton(beginningWith: Self.rowPrefix(name), unless: Self.errorTitles, file: file, line: line)
    }

    func chooseFirstAccount(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(addAccountButton, file: file, line: line)
        try expectAccount("Account 1", file: file, line: line)
        try driver.tap(row("Account 1"), file: file, line: line)
        let chosen = NSPredicate(format: "label BEGINSWITH %@ AND selected == true", Self.rowPrefix("Account 1"))
        try driver.waitFor(driver.app.buttons.matching(chosen).firstMatch, file: file, line: line)
    }

    func rename(_ name: String, to newName: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(infoButton(for: name), file: file, line: line)
        try driver.type(newName, into: nameField, file: file, line: line)
        try driver.tap(try driver.frontButton("Save Name", file: file, line: line), file: file, line: line)
    }

    func deleteAccount(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(infoButton(for: name), file: file, line: line)
        try driver.tap(deleteAccountButton, file: file, line: line)
        try driver.tap(try driver.frontButton("Delete Account", file: file, line: line), file: file, line: line)
    }
}
