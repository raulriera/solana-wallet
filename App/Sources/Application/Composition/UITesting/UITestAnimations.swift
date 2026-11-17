#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit

/// Turns off animations for a UI-test launch on the simulator, so tests don't wait for them.
enum UITestAnimations {
    /// The launch-environment key that turns animations off.
    static let environmentKey = "UI_TEST_DISABLE_ANIMATIONS"

    /// Whether this launch turns animations off.
    static let areDisabled = isRequested(in: ProcessInfo.processInfo.environment)

    /// Returns whether a launch environment turns animations off.
    ///
    /// - Parameter environment: The launch environment.
    /// - Returns: `true` when the environment sets ``environmentKey`` to `1`.
    static func isRequested(in environment: [String: String]) -> Bool {
        environment[environmentKey] == "1"
    }

    /// Turns off UIKit animations, such as navigation pushes, sheets, and alerts, when this launch asks for it.
    static func disableUIKitAnimations() {
        guard areDisabled else { return }
        UIView.setAnimationsEnabled(false)
    }

    /// Removes a transaction's animation and keeps views from adding their own when this launch asks for it.
    ///
    /// - Parameter transaction: The transaction to change.
    static func disableAnimations(in transaction: inout Transaction) {
        guard areDisabled else { return }
        transaction.animation = nil
        transaction.disablesAnimations = true
    }
}
#endif
