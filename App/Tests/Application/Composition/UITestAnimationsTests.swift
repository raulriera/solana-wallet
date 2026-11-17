#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import Testing
@testable import widgets

@MainActor
struct UITestAnimationsTests {
    @Test(arguments: [
        (["UI_TEST_DISABLE_ANIMATIONS": "1"], true),
        (["UI_TEST_DISABLE_ANIMATIONS": "0"], false),
        ([:], false),
    ])
    func `Only a launch that sets the flag to 1 turns animations off`(
        environment: [String: String],
        isRequested: Bool
    ) {
        #expect(UITestAnimations.isRequested(in: environment) == isRequested)
    }

    @Test
    func `A launch without the flag keeps a transaction's animation`() {
        var transaction = Transaction(animation: .default)

        UITestAnimations.disableAnimations(in: &transaction)

        #expect(transaction.animation == .default)
        #expect(!transaction.disablesAnimations)
    }
}
#endif
