import XCTest

@MainActor
struct PaymentsPage {
    private static let errors = [
        "Not Enough SOL", "Amount Too Small", "Couldn't Prepare Payment", "Couldn't Send Payment",
    ]

    let driver: UITestApp

    var sendButton: XCUIElement { driver.app.buttons["Send"] }

    func enterAmount(_ amount: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for character in amount {
            let key = character == "." ? "Decimal Point" : String(character)
            try driver.tap(driver.app.buttons[key], file: file, line: line)
        }
    }

    func review(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(driver.app.buttons["Review"], file: file, line: line)
        let ready = NSPredicate(format: "label == %@ AND enabled == true", "Send")
        try driver.expectOutcome(sendButton, matching: ready, unless: Self.errors, within: 30, file: file, line: line)
    }

    func send(file: StaticString = #filePath, line: UInt = #line) throws {
        try driver.tap(sendButton, file: file, line: line)
    }

    func expectSent(_ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let sent = NSPredicate(format: "label CONTAINS %@", message)
        try driver.expectOutcome(driver.text(containing: message), matching: sent, unless: Self.errors, within: 90,
                                 file: file, line: line)
    }
}
