import SwiftUI

/// Owns shared services for the lifetime of the app's windows.
@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["IS_UNIT_TESTING"] == "1" {
                // The Unit and Integration test plans set this, so the test host shows no window; services are still created.
                EmptyView()
            } else {
                WindowRoot(services: services)
            }
        }
    }
}
