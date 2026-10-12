import SwiftUI

/// Keeps Providers' choice, custom RPCs, and key preview current while Settings is on screen, runs each change, and
/// presents key entry, deletion confirmations, and failures.
///
/// It attaches to the settings split view, which stays on screen while Providers pushes screens; on compact displays
/// the split view merges those pushes into its own stack. So a failure to read the settings can alert on any Settings
/// destination.
struct ProvidersLifecycle: ViewModifier {
    @Bindable var flow: ProvidersFlow

    /// Reads the settings whenever any window changes them and awaits one change at a time.
    /// - Parameter content: The settings scene.
    /// - Returns: The scene with managed reads, changes, key entry, deletion confirmations, and failure
    ///   presentation.
    func body(content: Content) -> some View {
        let attempt = flow.attempt
        content
            .task(id: flow.revision.value) { await flow.reload() }
            .task(id: attempt) { await flow.run(attempt) }
            .sheet(item: $flow.keyEntry) { submission in
                // The sheet closes itself after a saved key; the choice that asked for the key continues.
                ProviderSetupSheet(submission: submission)
                    .onChange(of: submission.isSaved) { flow.keySaved() }
            }
            .alert("Delete RPC?", item: $flow.removal) { url in
                Button("Delete", role: .destructive) { flow.remove(url) }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                let host = Text(ProviderSettings.Provider.custom(url).name)
                if flow.selection == .custom(url) {
                    Text("\(host) will be deleted from this device, and every window will switch to Solana's public RPC.",
                         comment: "The Delete RPC alert's message for the RPC in use. The variable is the RPC's host.")
                } else {
                    Text("\(host) will be deleted from this device.",
                         comment: "The Delete RPC alert's message. The variable is the RPC's host.")
                }
            }
            .errorAlert($flow.error)
    }
}
