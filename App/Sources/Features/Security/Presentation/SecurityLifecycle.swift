import SwiftUI

/// Runs Security & Privacy's waiting steps while Settings is on screen and explains their failures.
///
/// It attaches to the settings split view, which stays on screen while Security & Privacy pushes
/// screens; on compact displays the split view merges those pushes into its own stack.
struct SecurityLifecycle: ViewModifier {
    @Bindable var coordinator: SecurityCoordinator

    /// Awaits one step at a time and presents secret-free failures.
    /// - Parameter content: The settings scene.
    /// - Returns: The scene with managed steps and failure presentation.
    func body(content: Content) -> some View {
        let attempt = coordinator.attempt
        content
            .task(id: attempt) { await coordinator.run(attempt) }
            .errorAlert($coordinator.error, retry: coordinator.reset)
    }
}
