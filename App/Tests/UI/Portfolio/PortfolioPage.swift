import XCTest

@MainActor
struct PortfolioPage {
    private static let additionErrorTitle = "Couldn't Add Token"

    let driver: UITestApp

    var addTokenButton: XCUIElement { driver.app.navigationBars.buttons["Add Token"] }
    var pasteButton: XCUIElement { driver.app.buttons["Paste"] }

    static func holdingLabel(beginningWith prefix: String) -> NSPredicate {
        NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@", XCUIElement.ElementType.button.rawValue, prefix)
    }

    func holding(_ prefix: String) -> XCUIElement {
        driver.app.buttons.matching(Self.holdingLabel(beginningWith: prefix)).firstMatch
    }

    func tokenDetails(_ name: String) -> XCUIElement {
        driver.app.navigationBars[name]
    }

    func open(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.portfolioTab, file: file, line: line)
    }

    func addToken(_ mint: String, previewing preview: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(addTokenButton, file: file, line: line)
        try driver.paste(mint)
        try driver.expectOutcome(driver.app.staticTexts[preview], matching: NSPredicate(format: "label == %@", preview),
                                 unless: [Self.additionErrorTitle], file: file, line: line)
        try driver.tap(try driver.frontButton("Add Token", file: file, line: line), file: file, line: line)
    }

    @discardableResult
    func expectAddedToken(_ prefix: String, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let token = holding(prefix)
        try driver.expectOutcome(token, matching: Self.holdingLabel(beginningWith: prefix),
                                 unless: [Self.additionErrorTitle], file: file, line: line)
        return token
    }

    func removeToken(_ token: XCUIElement, named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(token, file: file, line: line)
        try driver.tap(driver.app.buttons["More"], file: file, line: line)
        try driver.tap(driver.app.buttons["Remove Token"], file: file, line: line)
        let confirmation = driver.app.alerts["Remove \(name)?"]
        try driver.waitFor(confirmation, file: file, line: line)
        try driver.tap(confirmation.buttons["Remove"], file: file, line: line)
    }
}
