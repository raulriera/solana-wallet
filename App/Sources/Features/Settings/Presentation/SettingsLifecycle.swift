import SwiftUI

extension SettingsScene {
    /// Runs Security & Privacy's steps and Providers' reads and changes only while Settings is on screen.
    /// - Returns: The scene with both flows' managed work, prompts, and failure presentation.
    func settingsLifecycle() -> some View {
        modifier(SecurityLifecycle(flow: security).concat(ProvidersLifecycle(flow: providers)))
    }
}
