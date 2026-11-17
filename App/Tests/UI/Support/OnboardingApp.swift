import XCTest

@MainActor
struct OnboardingApp {
    static let phrase = OnboardingPage.phrase

    let driver = UITestApp()

    var app: XCUIApplication { driver.app }
    var submitImport: XCUIElement { onboarding.importWalletButton }
    var portfolioTab: XCUIElement { driver.portfolioTab }
    var settingsTab: XCUIElement { driver.settingsTab }
    private var onboarding: OnboardingPage { OnboardingPage(driver: driver) }
    private var portfolio: PortfolioPage { PortfolioPage(driver: driver) }

    static func holdingLabel(beginningWith prefix: String) -> NSPredicate {
        PortfolioPage.holdingLabel(beginningWith: prefix)
    }

    func launch() throws {
        driver.launch()
        try onboarding.expectWelcome()
    }

    func relaunch() {
        driver.relaunch()
    }

    func expectWelcome() throws {
        try onboarding.expectWelcome()
    }

    func expectWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.expectWallet(file: file, line: line)
    }

    func expectRPC(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.expectRPC(file: file, line: line)
    }

    func createWallet() throws {
        try onboarding.createWallet()
    }

    func openImport() throws {
        try onboarding.openImport()
    }

    func enterPhrase(_ phrase: String = OnboardingPage.phrase) throws {
        try onboarding.enterPhrase(phrase)
    }

    func enterPassphrase(_ passphrase: String) throws {
        try onboarding.enterPassphrase(passphrase)
    }

    func openWallet(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.openWallet(file: file, line: line)
    }

    func connectProvider(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.connectProvider(file: file, line: line)
    }

    func showPortfolio(file: StaticString = #filePath, line: UInt = #line) throws {
        try onboarding.expectWallet(file: file, line: line)
        try portfolio.open(file: file, line: line)
    }

    func holding(_ prefix: String) -> XCUIElement {
        portfolio.holding(prefix)
    }

    func openSecurity(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(settingsTab, file: file, line: line)
        try driver.tap(app.buttons["Security & Privacy"], file: file, line: line)
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
