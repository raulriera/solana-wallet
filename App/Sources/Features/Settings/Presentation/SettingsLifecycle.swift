import SwiftUI

extension SettingsSplitView {
    /// Runs the Security & Privacy, RPC, and Prices workflows while Settings is on screen.
    ///
    /// - Returns: The split view with the workflows' tasks, prompts, and alerts.
    func settingsLifecycle() -> some View {
        modifier(SecurityLifecycle(coordinator: security)
            .concat(RPCLifecycle(coordinator: rpcCoordinator))
            .concat(PricesLifecycle(coordinator: pricesCoordinator)))
    }
}
