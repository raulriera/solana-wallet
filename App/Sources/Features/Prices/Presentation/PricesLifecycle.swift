import SwiftUI

/// Reads the price provider choice, runs each change, and presents errors.
struct PricesLifecycle: ViewModifier {
    @Bindable var coordinator: PricesCoordinator

    func body(content: Content) -> some View {
        let attempt = coordinator.attempt
        content
            .task { await coordinator.load() }
            .task(id: attempt) { await coordinator.run(attempt) }
            .alert(error: $coordinator.error)
    }
}
