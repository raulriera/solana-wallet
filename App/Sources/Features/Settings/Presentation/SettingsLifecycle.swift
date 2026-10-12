import SwiftUI

extension SettingsScene {
    /// Runs Security & Privacy's steps and Providers' reads and changes only while Settings is on screen.
    /// - Parameters:
    ///   - security: The owning window's Security & Privacy flow.
    ///   - providers: The owning window's Providers flow.
    /// - Returns: The scene with both flows' managed work, prompts, and failure presentation.
    func settingsLifecycle(security: SecurityFlow, providers: ProvidersFlow) -> some View {
        modifier(SecurityLifecycle(flow: security).concat(ProvidersLifecycle(flow: providers)))
    }
}
