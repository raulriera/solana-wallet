import UIKit

/// The app delegate that refuses third-party keyboards and, in a UI-test launch, turns off UIKit animations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        UITestAnimations.disableUIKitAnimations()
        #endif
        return true
    }

    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
