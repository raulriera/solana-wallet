import SwiftUI

/// The app, which holds the services its windows share.
@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["IS_UNIT_TESTING"] == "1" {
                EmptyView()
            } else {
                WindowRoot(services: services)
            }
        }
    }
}
