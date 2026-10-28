import SwiftUI

extension SettingsSplitView {
    /// Runs Security & Privacy's steps and Providers' reads and changes only while Settings is on screen.
    /// - Returns: The split view with both flows' managed work, prompts, and failure presentation.
    func settingsLifecycle() -> some View {
        modifier(SecurityLifecycle(coordinator: security).concat(ProvidersLifecycle(coordinator: providers)))
    }
}
