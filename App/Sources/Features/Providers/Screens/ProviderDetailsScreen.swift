import SwiftUI

/// Shows Helius's saved key, mostly hidden, and opens the screen that adds or changes it.
struct ProviderDetailsScreen: View {
    @Environment(\.palette) private var palette
    /// The saved key with all but its first characters masked, or `nil` when no key is saved.
    let keyPreview: String?
    let actions: any ProviderActions

    var body: some View {
        let footer: LocalizedStringResource = keyPreview == nil
            ? "Your wallets use this key for balances and live updates."
            : "Your wallets use this key for balances and live updates. It's stored only on this device, and most of it is hidden."

        Form {
            Section {
                if let keyPreview {
                    Text(verbatim: keyPreview)
                        .foregroundStyle(palette.primaryText)
                        .accessibilityLabel(Text(keyPreview, format: .spokenMasked))
                } else {
                    Text("None", comment: "Shown in place of the RPC API key when no key is saved.")
                        .foregroundStyle(palette.secondaryText)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text(footer)
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)

            Section {
                // The button names the screen it opens.
                Button(ProviderEntryPurpose(keyPreview: keyPreview).title, action: actions.changeKey)
                    .foregroundStyle(palette.accent)
            }
            .listRowBackground(palette.surface)
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(Text(ProviderSettings.Provider.helius.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
