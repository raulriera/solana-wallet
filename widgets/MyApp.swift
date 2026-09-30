import SwiftUI

@main struct MyApp: App {
    @State private var appearance = AppearanceCoordinator(
        store: AppearanceStore(), recovery: SettingsRecoveryRequest()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modifier(AppearanceLifecycle(appearance: appearance))
        }
    }
}
