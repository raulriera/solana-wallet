import XCTest

@MainActor
struct PortfolioPage {
    let driver: UITestApp

    static func holdingLabel(beginningWith prefix: String) -> NSPredicate {
        NSPredicate(format: "elementType == %lu AND label BEGINSWITH %@", XCUIElement.ElementType.button.rawValue, prefix)
    }

    func holding(_ prefix: String) -> XCUIElement {
        driver.app.buttons.matching(Self.holdingLabel(beginningWith: prefix)).firstMatch
    }

    func open(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.portfolioTab, file: file, line: line)
    }
}
