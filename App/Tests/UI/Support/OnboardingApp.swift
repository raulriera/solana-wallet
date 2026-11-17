import XCTest

@MainActor
struct OnboardingApp {
    let driver = UITestApp()

    var app: XCUIApplication { driver.app }
    var settingsTab: XCUIElement { driver.settingsTab }
    private var onboarding: OnboardingPage { OnboardingPage(driver: driver) }

    func launch() throws {
        driver.launch()
        try onboarding.expectWelcome()
    }

    func relaunch() {
        driver.relaunch()
    }

    func expectWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.expectWallet(file: file, line: line)
    }

    func createWallet() throws {
        try onboarding.createWallet()
    }

    func openWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.openWallet(file: file, line: line)
    }

    func frontButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try driver.frontButton(label, file: file, line: line)
    }

    func paste(_ text: String) throws {
        try driver.paste(text)
    }

    func expectOutcome(_ destination: XCUIElement, matching outcome: NSPredicate, unless alerts: [String],
                       file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.expectOutcome(destination, matching: outcome, unless: alerts, file: file, line: line)
    }

    func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.waitFor(element, file: file, line: line)
    }

    func waitForAbsence(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.waitForAbsence(element, file: file, line: line)
    }

    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(element, file: file, line: line)
    }
}
