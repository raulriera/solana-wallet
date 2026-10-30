import Testing
import UIKit
@testable import widgets

@MainActor
struct AppDelegateTests {
    @Test
    func `Third-party keyboards are refused app-wide`() {
        let delegate = AppDelegate()
        #expect(!delegate.application(UIApplication.shared, shouldAllowExtensionPointIdentifier: .keyboard))
    }
}
