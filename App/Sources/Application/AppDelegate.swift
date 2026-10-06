import UIKit

/// Keeps third-party keyboards away from recovery words and the provider key.
///
/// `SecureField` already forces the system keyboard; the revealed recovery field does not,
/// and SwiftUI has no way to refuse keyboard extensions, so the app delegate does it for every field.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Refuses custom keyboard extensions app-wide; every other extension point keeps its default.
    /// - Parameters:
    ///   - application: The running app.
    ///   - extensionPointIdentifier: The extension point the system is about to use.
    /// - Returns: `false` for keyboards, otherwise `true`.
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
