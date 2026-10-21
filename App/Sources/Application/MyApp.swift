import SwiftUI

/// Owns shared services for the lifetime of the app's windows.
@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["IS_UNIT_TESTING"] == "1" {
                // The widgets scheme's Test action sets this; unit tests build their own services.
                EmptyView()
            } else {
                WindowRoot(services: services)
            }
        }
    }
}
