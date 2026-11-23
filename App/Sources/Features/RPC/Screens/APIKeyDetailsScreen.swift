import SwiftUI

/// Shows the saved API key, mostly hidden, and opens the screen that adds or changes it.
struct APIKeyDetailsScreen: View {
    /// The saved key with all but its first characters masked, or `nil` when no key is saved.
    let keyPreview: String?
    let actions: any RPCActions

    var body: some View {
        let footer: LocalizedStringResource = keyPreview == nil
            ? "Your wallets use this key for balances and live updates."
            : "Your wallets use this key for balances and live updates. It's stored only on this device, and most of it is hidden."

        Form {
            Section {
                if let keyPreview {
                    Text(verbatim: keyPreview)
                        .accessibilityLabel(Text(keyPreview, format: .spokenMasked))
                } else {
                    Text("None", comment: "Shown in place of the RPC API key when no key is saved.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text(footer)
            }

            Section {
                Button(RPCEntryPurpose(keyPreview: keyPreview).title, action: actions.changeKey)
            }
        }
        .navigationTitle(Text(RPCSettings.Provider.helius.name))
        .toolbarTitleDisplayMode(.inline)
    }
}
