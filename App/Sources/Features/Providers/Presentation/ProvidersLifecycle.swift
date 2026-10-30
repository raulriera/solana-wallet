import SwiftUI

/// Reads the provider settings, runs each change, and presents key entry, deletion confirmations, and failures.
struct ProvidersLifecycle: ViewModifier {
    @Environment(ProviderStore.self) private var providers
    @Bindable var coordinator: ProvidersCoordinator

    func body(content: Content) -> some View {
        let attempt = coordinator.attempt
        content
            .task { await coordinator.load() }
            .task(id: attempt) { await coordinator.run(attempt) }
            .sheet(item: $coordinator.keyEntry, onDismiss: coordinator.keySaved) { ProviderSetupSheet(submission: $0) }
            .alert("Delete RPC?", item: $coordinator.removal) { url in
                Button("Delete", role: .destructive) { coordinator.remove(url) }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                let host = Text(ProviderSettings.Provider.custom(url).name)
                if providers.settings?.selection == .custom(url) {
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
