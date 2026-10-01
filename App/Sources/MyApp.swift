import SwiftUI

/// Owns shared services for the lifetime of the app's windows.
@main struct MyApp: App {
    @State private var services = Result { try AppServices() }

    var body: some Scene {
        WindowGroup {
            switch services {
            case .success(let services): WindowRoot(services: services.appearance)
            case .failure:
                ContentUnavailableView("Appearance Unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The original theme could not be loaded."))
            }
        }
    }
}
