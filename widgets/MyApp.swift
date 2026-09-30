import SwiftUI

@main struct MyApp: App {
    @State private var services = Result { try AppearanceServices() }

    var body: some Scene {
        WindowGroup {
            switch services {
            case .success(let services): AppearanceScene(services: services)
            case .failure:
                ContentUnavailableView("Appearance Unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The original theme could not be loaded."))
            }
        }
    }
}
