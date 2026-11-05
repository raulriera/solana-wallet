import SwiftUI

/// Shows a custom RPC's masked URL and deletes the RPC after the person confirms.
struct CustomRPCDetailsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let url: URL
    /// Whether the RPC is still in the list.
    let isListed: Bool
    /// The custom RPC waiting for the person to confirm its deletion.
    @Binding var removal: URL?
    let actions: any RPCActions

    var body: some View {
        Form {
            Section {
                Text(url, format: .maskedURL)
                    .foregroundStyle(palette.text)
                    .accessibilityLabel(Text(url, format: .spokenMaskedURL))
            } header: {
                Text("URL")
            } footer: {
                Text("Your wallets use this RPC for balances and live updates. Part of its URL is hidden because it can contain a key.")
                    .foregroundStyle(palette.secondaryText)
            }

            Section {
                Button("Delete RPC", systemImage: "trash", role: .destructive) { removal = url }
                    .labelStyle(.warning)
                    .rpcDeletion(of: url, removal: $removal, actions: actions)
            }
        }
        .navigationTitle(Text(RPCSettings.Provider.custom(url).name))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isListed) { dismiss() }
    }
}
