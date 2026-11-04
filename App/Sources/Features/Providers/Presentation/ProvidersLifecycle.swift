import SwiftUI

/// Reads the provider settings, runs each change, and presents key entry and failures.
struct ProvidersLifecycle: ViewModifier {
    @Bindable var coordinator: ProvidersCoordinator

    func body(content: Content) -> some View {
        let attempt = coordinator.attempt
        content
            .task { await coordinator.load() }
            .task(id: attempt) { await coordinator.run(attempt) }
            .sheet(item: $coordinator.keyEntry, onDismiss: coordinator.keySaved) { ProviderSetupSheet(submission: $0) }
            .alert(error: $coordinator.error)
    }
}
