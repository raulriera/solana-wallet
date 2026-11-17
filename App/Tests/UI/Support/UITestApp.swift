import Foundation
import UIKit
import XCTest

@MainActor
struct UITestApp {
    enum Swipe { case up, down }

    private enum Error: Swift.Error { case missingElement, unexpectedElement, unavailableControl, reportedError, unexpectedState }

    let app = XCUIApplication()

    var portfolioTab: XCUIElement { app.buttons["Portfolio"].firstMatch }
    var settingsTab: XCUIElement { app.buttons["Settings"].firstMatch }

    init() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func launch() {
        app.launchEnvironment["UI_TEST_RESET"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "UI_TEST_RESET")
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

    func reveal(_ element: XCUIElement, swiping swipe: Swipe) {
        guard !element.isHittable else { return }
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
        try tap(app.buttons["Paste"])
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "pasted from")).firstMatch
        _ = banner.waitForExistence(timeout: 2)
        try waitForAbsence(banner)
    }

    func expectOutcome(_ destination: XCUIElement, matching outcome: NSPredicate, unless alerts: [String],
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let reports = alerts.map { NSPredicate(format: "label == %@", $0) }
        let either = NSCompoundPredicate(orPredicateWithSubpredicates: [outcome] + reports)
        try waitFor(app.descendants(matching: .any).matching(either).firstMatch, file: file, line: line)
        if let alert = alerts.first(where: { app.alerts[$0].exists }) {
            XCTFail("The app reported \(alert) instead of the expected result.", file: file, line: line)
            throw Error.reportedError
        }
        try waitFor(destination, file: file, line: line)
    }

    func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForExistence(timeout: 10) else {
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

    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        let predicate = NSPredicate(format: "exists == true AND isHittable == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: 10) == .completed else {
            XCTFail("Expected control did not become ready", file: file, line: line)
            throw Error.unavailableControl
        }
        element.tap()
    }
}
