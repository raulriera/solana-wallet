import XCTest

@MainActor
struct SettingsPage {
    let driver: UITestApp

    func open(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.settingsTab, file: file, line: line)
    }

    func switchNetwork(to network: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try open(file: file, line: line)
        try driver.tap(driver.app.buttons["Network"], file: file, line: line)
        try driver.tap(driver.app.buttons[network], file: file, line: line)
        let chosen = NSPredicate(format: "label == %@ AND selected == true", network)
        try driver.waitFor(driver.app.buttons.matching(chosen).firstMatch, file: file, line: line)
    }

    @discardableResult
    func openSecurity(file: StaticString = #filePath, line: UInt = #line) throws -> SecurityPage {
        try open(file: file, line: line)
        try driver.tap(driver.app.buttons["Security & Privacy"], file: file, line: line)
        return SecurityPage(driver: driver)
    }
}
