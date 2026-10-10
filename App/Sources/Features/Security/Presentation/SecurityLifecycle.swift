import SwiftUI

/// Runs Security & Privacy's waiting steps while Settings is on screen and explains their failures.
///
/// It attaches to the settings split view, which stays on screen while Security & Privacy pushes
/// screens; on compact displays the split view merges those pushes into its own stack.
private struct SecurityLifecycle: ViewModifier {
    @Bindable var flow: SecurityFlow

    /// Awaits one step at a time and presents secret-free failures.
    /// - Parameter content: The settings scene.
    /// - Returns: The scene with managed steps and failure presentation.
    func body(content: Content) -> some View {
        let attempt = flow.attempt
        content
            .task(id: attempt) { await flow.run(attempt) }
            .errorAlert($flow.error) { error in
                if error == .resetIncomplete {
                    Button("Try Again", action: flow.reset)
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            }
    }
}

extension SettingsScene {
    /// Runs the Security & Privacy flow's steps only while Settings is on screen.
    /// - Parameter flow: The owning window's Security & Privacy flow.
    /// - Returns: The scene with managed steps and failure presentation.
    func securityLifecycle(_ flow: SecurityFlow) -> some View {
        modifier(SecurityLifecycle(flow: flow))
    }
}
