import SwiftUI

/// Shows a custom RPC's URL, masked so a key in it stays hidden, and deletes the RPC after the person confirms.
struct CustomRPCDetailsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let url: URL
    /// Whether the RPC is still in the list; the screen closes itself once any window deletes it.
    let isListed: Bool
    /// The custom RPC waiting for the person to confirm its deletion.
    @Binding var removal: URL?

    var body: some View {
        Form {
            Section {
                Text(url, format: .maskedURL)
                    .foregroundStyle(palette.primaryText)
                    .accessibilityLabel(Text(url, format: .spokenMaskedURL))
            } header: {
                Text("URL")
            } footer: {
                Text("Your wallets use this RPC for balances and live updates. Part of its URL is hidden because it can contain a key.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)

            Section {
                Button("Delete RPC", systemImage: "trash", role: .destructive) { removal = url }
                    .labelStyle(.warning)
            }
            .listRowBackground(palette.surface)
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(Text(ProviderSettings.Provider.custom(url).name))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isListed) { dismiss() }
    }
}
