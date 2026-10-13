import SwiftUI

/// Keeps Providers' choice, custom RPCs, and key preview current while Settings or onboarding is on screen, runs each
/// change, and presents key entry, deletion confirmations, and failures.
///
/// It attaches to the container that stays on screen while Providers pushes screens: the settings split view, which
/// merges those pushes into its own stack on compact displays, or onboarding's navigation stack. So a failure to read
/// the settings can alert on any screen of that container.
struct ProvidersLifecycle: ViewModifier {
    @Bindable var coordinator: ProvidersCoordinator

    /// Reads the settings whenever any window changes them and awaits one change at a time.
    /// - Parameter content: The settings or onboarding scene.
    /// - Returns: The scene with managed reads, changes, key entry, deletion confirmations, and failure
    ///   presentation.
    func body(content: Content) -> some View {
        let attempt = coordinator.attempt
        content
            .task(id: coordinator.revision.value) { await coordinator.reload() }
            .task(id: attempt) { await coordinator.run(attempt) }
            .sheet(item: $coordinator.keyEntry) { ProviderSetupSheet(submission: $0) }
            // The sheet closes itself after a saved key, before its own content could react, so the choice that asked
            // for the key continues from here.
            .onChange(of: coordinator.isKeyChoiceSaved) { coordinator.keySaved() }
            .alert("Delete RPC?", item: $coordinator.removal) { url in
                Button("Delete", role: .destructive) { coordinator.remove(url) }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                let host = Text(ProviderSettings.Provider.custom(url).name)
                if coordinator.selection == .custom(url) {
                    Text("\(host) will be deleted from this device, and every window will switch to Solana's public RPC.",
                         comment: "The Delete RPC alert's message for the RPC in use. The variable is the RPC's host.")
                } else {
                    Text("\(host) will be deleted from this device.",
                         comment: "The Delete RPC alert's message. The variable is the RPC's host.")
                }
            }
            .errorAlert($coordinator.error)
    }
}
