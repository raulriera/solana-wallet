import XCTest

@MainActor
struct RPCPage {
    static let errorTitles = [
        "Too Many Requests", "Couldn't Connect", "Couldn't Save API Key", "Couldn't Load Provider",
        "Couldn't Change Provider",
    ]

    let driver: UITestApp

    var keySheet: XCUIElement { driver.app.navigationBars["Connect to Helius"] }
    var keyField: XCUIElement { driver.app.secureTextFields["RPC API key"] }

    func chooseHelius(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Helius"], file: file, line: line)
        try expectOutcome(keySheet, label: "Connect to Helius", file: file, line: line)
    }

    func hittableContinueButton(file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try driver.frontButton("Continue", file: file, line: line)
    }

    func submitKey(_ key: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.type(key, into: keyField, file: file, line: line)
        try driver.tap(try hittableContinueButton(file: file, line: line), file: file, line: line)
    }

    func expectKeyRejected(file: StaticString = #filePath, line: UInt = #line) throws {
        let message = "Your provider didn't accept this API key. Check it and try again."
        try expectOutcome(driver.app.staticTexts[message], label: message, file: file, line: line)
    }

    func expectChosen(_ provider: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let chosen = NSPredicate(format: "label == %@ AND selected == true", provider)
        try driver.expectOutcome(driver.app.buttons.matching(chosen).firstMatch, matching: chosen,
                                 unless: Self.errorTitles, within: 30, file: file, line: line)
    }

    private func expectOutcome(_ destination: XCUIElement, label: String, file: StaticString, line: UInt) throws {
        try driver.expectOutcome(destination, matching: NSPredicate(format: "label == %@", label),
                                 unless: Self.errorTitles, file: file, line: line)
    }
}
