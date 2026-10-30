import SwiftUI

extension SettingsSplitView {
    /// Runs the Security & Privacy and Providers workflows while Settings is on screen.
    ///
    /// - Returns: The split view with both workflows' tasks, prompts, and alerts.
    func settingsLifecycle() -> some View {
        modifier(SecurityLifecycle(coordinator: security).concat(ProvidersLifecycle(coordinator: providers)))
    }
}
