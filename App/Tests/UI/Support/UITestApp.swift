import Foundation
import UIKit
import XCTest
import notify

@MainActor
struct UITestApp {
    enum Swipe { case up, down }

    enum PreparedWallet {
        case newWallet
        case importedWallet(String)

        var environmentValue: String {
            switch self {
            case .newWallet: "new"
            case .importedWallet(let phrase): phrase
            }
        }

        static var devWallet: Self { .importedWallet(ProcessInfo.processInfo.environment["DEVNET_TEST_SEED"]!) }
    }

    private enum Error: Swift.Error { case missingElement, unexpectedElement, unavailableControl, reportedError, unexpectedState }

    let app = XCUIApplication()

    var portfolioTab: XCUIElement { app.buttons["Portfolio"].firstMatch }
    var contactsTab: XCUIElement { app.buttons["Contacts"].firstMatch }
    var settingsTab: XCUIElement { app.buttons["Settings"].firstMatch }
    var pasteButton: XCUIElement { app.buttons["Paste"] }

    private static func buttonLabel(beginningWith prefix: String) -> NSPredicate {
        NSPredicate(
            format: "elementType == %lu AND label BEGINSWITH %@",
            XCUIElement.ElementType.button.rawValue,
            prefix
        )
    }

    init() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UI_TEST_DISABLE_ANIMATIONS"] = "1"
    }

    func launch(with wallet: PreparedWallet? = nil) {
        app.launchEnvironment["UI_TEST_RESET"] = "1"
        app.launchEnvironment["UI_TEST_WALLET"] = wallet?.environmentValue
        app.launch()
        app.launchEnvironment.removeValue(forKey: "UI_TEST_RESET")
        app.launchEnvironment.removeValue(forKey: "UI_TEST_WALLET")
    }

    func relaunch() {
        app.terminate()
        app.launch()
    }

    func terminate() {
        app.terminate()
    }

    func returnFromBackground(file: StaticString = #filePath, line: UInt = #line) throws {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").activate()
        guard app.wait(for: .runningBackground, timeout: 10) else {
            XCTFail("The app did not enter the background", file: file, line: line)
            throw Error.unexpectedState
        }
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 10) else {
            XCTFail("The app did not return to the foreground", file: file, line: line)
            throw Error.unexpectedState
        }
    }

    func button(beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(Self.buttonLabel(beginningWith: prefix)).firstMatch
    }

    @discardableResult
    func expectButton(
        beginningWith prefix: String,
        unless alerts: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let button = button(beginningWith: prefix)
        let label = Self.buttonLabel(beginningWith: prefix)
        try expectOutcome(button, matching: label, unless: alerts, file: file, line: line)
        return button
    }

    func text(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        ).firstMatch
    }

    func matchFaceID(file: StaticString = #filePath, line: UInt = #line) throws {
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").staticTexts["Face ID"]
        try waitFor(prompt, file: file, line: line)
        notify_post("com.apple.BiometricKit_Sim.pearl.match")
        try waitForAbsence(prompt, file: file, line: line)
    }

    func reveal(
        _ element: XCUIElement,
        swiping swipe: Swipe,
        until isShown: KeyPath<XCUIElement, Bool> = \.isHittable
    ) {
        guard !element[keyPath: isShown] else { return }
        switch swipe {
        case .up: app.swipeUp()
        case .down: app.swipeDown()
        }
    }

    func frontButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try XCTUnwrap(app.buttons.matching(identifier: label).allElementsBoundByIndex.first(where: \.isHittable),
                      "No tappable \(label) button", file: file, line: line)
    }

    func paste(_ text: String) throws {
        UIPasteboard.general.string = text
        try tap(pasteButton)
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "pasted from")).firstMatch
        _ = banner.waitForExistence(timeout: 2)
        try waitForAbsence(banner)
    }

    func expectOutcome(_ destination: XCUIElement, matching outcome: NSPredicate, unless alerts: [String],
                       within timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) throws {
        let reports = alerts.map { NSPredicate(format: "label == %@", $0) }
        let either = NSCompoundPredicate(orPredicateWithSubpredicates: [outcome] + reports)
        let result = app.descendants(matching: .any).matching(either).firstMatch
        try waitFor(result, within: timeout, file: file, line: line)
        if let alert = alerts.first(where: { app.alerts[$0].exists }) {
            XCTFail("The app reported \(alert) instead of the expected result.", file: file, line: line)
            throw Error.reportedError
        }
        try waitFor(destination, file: file, line: line)
    }

    func waitFor(_ element: XCUIElement, within timeout: TimeInterval = 10, file: StaticString = #filePath,
                 line: UInt = #line) throws {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Expected UI did not appear", file: file, line: line)
            throw Error.missingElement
        }
    }

    func waitForAbsence(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForNonExistence(timeout: 10) else {
            XCTFail("UI that should be gone is still on screen", file: file, line: line)
            throw Error.unexpectedElement
        }
    }

    func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        try tap(field, file: file, line: line)
        field.typeText(text)
    }

    func tap(_ element: XCUIElement, within timeout: TimeInterval = 10, unless alerts: [String] = [],
             file: StaticString = #filePath, line: UInt = #line) throws {
        let reports = alerts.map { app.alerts[$0] }
        let predicate = NSPredicate { _, _ in
            element.exists && element.isEnabled && element.isHittable || reports.contains { $0.exists }
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail("Expected control did not become ready", file: file, line: line)
            throw Error.unavailableControl
        }
        if let alert = alerts.first(where: { app.alerts[$0].exists }) {
            XCTFail("The app reported \(alert) instead of the expected result.", file: file, line: line)
            throw Error.reportedError
        }
        element.tap()
    }
}
