import XCTest

@MainActor
struct SecurityPage {
    let driver: UITestApp

    var accountPath: XCUIElement { driver.text(containing: "m/44'/501'/") }

    func recoveryWord(_ word: some StringProtocol, at position: Int) -> XCUIElement {
        driver.app.staticTexts["\(position). \(word)"]
    }

    func showRecoveryPhrase(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Show Recovery Phrase"], file: file, line: line)
        try driver.waitFor(driver.app.navigationBars["Recovery Phrase"], file: file, line: line)
    }

    func resetApp(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.collectionViews.buttons["Reset App"], file: file, line: line)
        try driver.matchFaceID(file: file, line: line)
        try driver.tap(driver.app.buttons["Continue"], file: file, line: line)
        try driver.tap(driver.app.collectionViews.buttons["Reset App"], file: file, line: line)
        let confirmation = driver.app.sheets["Reset App?"]
        try driver.waitFor(confirmation, file: file, line: line)
        try driver.tap(confirmation.buttons["Reset App"], file: file, line: line)
    }
}
