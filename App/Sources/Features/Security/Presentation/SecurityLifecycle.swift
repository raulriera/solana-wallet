import SwiftUI

/// Runs Security & Privacy's waiting steps and presents their errors.
struct SecurityLifecycle: ViewModifier {
    @Bindable var coordinator: SecurityCoordinator

    func body(content: Content) -> some View {
        let attempt = coordinator.attempt
        content
            .task(id: attempt) { await coordinator.run(attempt) }
            .errorAlert($coordinator.error, retry: coordinator.reset)
    }
}
