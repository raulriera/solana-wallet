import SwiftUI

/// Collects the RPC provider's API key; the owning scene checks and saves it.
struct ProviderSetupScreen: View {
    @Environment(\.palette) private var palette
    @State private var input = ProviderKeyInput()
    @State private var contentInset = LayoutMetrics.contentMargin
    @FocusState private var isKeyFocused: Bool
    let isKeyRejected: Bool
    let submit: (String) -> Void

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Connect to Helius",
                    message: "This wallet connects directly to Solana through Helius. Enter your Helius API key to load your balances.",
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                )
            }
            .listRowBackground(palette.surface)

            Section {
                ProviderKeyEntry(input: input, isFocused: $isKeyFocused)
                    .foregroundStyle(palette.primaryText)

                if isKeyRejected {
                    Label(ProviderConnectionError.invalidKey.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                }
            } header: {
                Text("API Key")
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your key is stored only on this device and is sent only to Helius.")
                        .foregroundStyle(palette.secondaryText)
                    Link("Get an API key from Helius", destination: URL(string: "https://dashboard.helius.dev")!)
                }
                .font(.footnote)
            }
            .listRowBackground(palette.surface)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Continue", action: submitKey)
                .buttonStyle(.primary)
                .disabled(!input.hasKey)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Connect to Helius")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Dismisses the keyboard so the result stays visible, then hands the key to the scene.
    private func submitKey() {
        isKeyFocused = false
        submit(input.key)
    }
}

#Preview("Empty") {
    NavigationStack {
        ProviderSetupScreen(isKeyRejected: false, submit: { _ in })
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Rejected key") {
    NavigationStack {
        ProviderSetupScreen(isKeyRejected: true, submit: { _ in })
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}
