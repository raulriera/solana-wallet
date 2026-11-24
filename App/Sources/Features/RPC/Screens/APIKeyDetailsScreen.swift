import SwiftUI

/// Shows the saved API key, mostly hidden, and opens the screen that adds or changes it.
struct APIKeyDetailsScreen: View {
    /// The saved key with all but its first characters masked, or `nil` when no key is saved.
    let keyPreview: String?
    let actions: any RPCActions

    var body: some View {
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
                if keyPreview != nil {
                    Text("Part of the key is hidden.")
                }
            }

            Section {
                Button(RPCEntryPurpose(keyPreview: keyPreview).title, action: actions.changeKey)
            }
        }
        .navigationTitle(Text(RPCSettings.Provider.helius.name))
        .toolbarTitleDisplayMode(.inline)
    }
}
