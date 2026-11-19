import XCTest

@MainActor
struct PrivateBalancePage {
    private static let errors = [
        "Private Balance Unavailable", "Can't Complete Transaction", "Not Enough SOL", "Can't Prepare Transaction",
        "Couldn't Send Transaction", "Couldn't Turn On Private Balance", "Amount Too Large for One Transaction",
    ]

    let driver: UITestApp

    var turnOnButton: XCUIElement { driver.app.buttons["Turn On Private Balance"] }

    func formButton(_ title: String) -> XCUIElement {
        driver.app.collectionViews.buttons[title]
    }

    func turnOn(file: StaticString = #filePath, line: UInt = #line) throws {
        driver.reveal(turnOnButton, swiping: .up)
        try driver.tap(turnOnButton, file: file, line: line)
        try expectOutcome(formButton("Make SOL Private"), label: "Make SOL Private", within: 60, file: file, line: line)
    }

    func startMove(_ title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let move = formButton(title)
        try driver.waitFor(move, within: 90, file: file, line: line)
        driver.reveal(move, swiping: .up)
        try driver.tap(move, file: file, line: line)
    }

    func reviewButton(_ title: String) -> XCUIElement {
        driver.app.collectionViews.containing(NSPredicate(format: "label BEGINSWITH %@", "Network Fee"))
            .buttons[title]
    }

    func review(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Review"], file: file, line: line)
    }

    func approve(_ title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(reviewButton(title), within: 120, file: file, line: line)
    }

    func expectResult(_ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try expectOutcome(driver.text(containing: message), label: message, within: 120, file: file, line: line)
    }

    private func expectOutcome(_ destination: XCUIElement, label: String, within timeout: TimeInterval,
                               file: StaticString, line: UInt) throws {
        try driver.expectOutcome(destination, matching: NSPredicate(format: "label CONTAINS %@", label),
                                 unless: Self.errors, within: timeout, file: file, line: line)
    }
}
