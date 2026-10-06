import Testing
import UIKit
@testable import widgets

/// Checks the app-wide extension policy that protects typed secrets.
@MainActor
struct AppDelegateTests {
    /// Custom keyboards are refused, so recovery words and the provider key only reach the system keyboard.
    @Test
    func `Third-party keyboards are refused app-wide`() {
        let delegate = AppDelegate()
        #expect(!delegate.application(UIApplication.shared, shouldAllowExtensionPointIdentifier: .keyboard))
    }
}
