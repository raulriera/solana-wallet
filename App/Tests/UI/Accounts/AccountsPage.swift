import XCTest

@MainActor
struct AccountsPage {
    private static let errorTitles = ["Couldn't Add Account", "Couldn't Rename Account", "Couldn't Delete Account"]

    let driver: UITestApp

    var addAccountButton: XCUIElement { driver.app.buttons["Add Account"] }
    var nameField: XCUIElement { driver.app.textFields["Name"] }
    var deleteAccountButton: XCUIElement { driver.app.buttons["Delete Account"] }
    var deletionError: XCUIElement { driver.app.alerts["Couldn't Delete Account"] }

    private static func rowLabel(beginningWith name: String) -> NSPredicate {
        NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@", XCUIElement.ElementType.button.rawValue,
                    name + ",")
    }

    func row(_ name: String) -> XCUIElement {
        driver.app.buttons.matching(Self.rowLabel(beginningWith: name)).firstMatch
    }

    func infoButton(for name: String) -> XCUIElement {
        driver.app.buttons["More Info About \(name)"].firstMatch
    }

    func expectShown(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.waitFor(driver.app.navigationBars["Accounts"], file: file, line: line)
    }

    func expectAccount(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.expectOutcome(row(name), matching: Self.rowLabel(beginningWith: name), unless: Self.errorTitles,
                                 file: file, line: line)
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
