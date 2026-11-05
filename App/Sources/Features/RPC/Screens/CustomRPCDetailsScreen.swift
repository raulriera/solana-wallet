import SwiftUI

/// Shows a custom RPC's masked URL and deletes the RPC after the person confirms.
struct CustomRPCDetailsScreen: View {
    let url: URL
    /// Whether the RPC is still in the list.
    let isListed: Bool
    /// The custom RPC waiting for the person to confirm its deletion.
    @Binding var removal: URL?
    let actions: any RPCActions

    var body: some View {
        MaskedURLDetails(
            url: url,
            title: RPCSettings.Provider.custom(url).name,
            footer: "Your wallets use this RPC for balances and live updates. Part of its URL is hidden because it can contain a key.",
            isListed: isListed
        ) {
            Button("Delete RPC", systemImage: "trash", role: .destructive) { removal = url }
                .labelStyle(.warning)
                .lineLimit(1)
                .rpcDeletion(of: url, removal: $removal, actions: actions)
        }
    }
}
