import SwiftUI

/// Owns shared services for the lifetime of the app's windows.
@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = Result { try AppServices() }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["IS_UNIT_TESTING"] == "1" {
                // The widgets scheme's Test action sets this; unit tests build their own services.
                EmptyView()
            } else {
                switch services {
                case .success(let services):
                    WindowRoot(services: services)
                case .failure:
                    #warning("Incorrect message, this also needs either a recoverable step or description of the failure")
                    ContentUnavailableView("Appearance Unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text("The original theme could not be loaded."))
                        .drawOnAppear()
                }
            }
        }
    }
}
