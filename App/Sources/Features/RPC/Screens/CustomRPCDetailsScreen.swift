import SwiftUI

/// Shows a custom RPC's masked URL and deletes the RPC after the person confirms.
struct CustomRPCDetailsScreen: View {
    let url: URL
    /// Whether the RPC is still in the list.
    let isListed: Bool
    /// Whether the RPC is the provider in use.
    let isSelected: Bool
    let actions: any RPCActions
    @State private var removal: URL?

    var body: some View {
        MaskedURLDetails(
            url: url,
            title: RPCSettings.Provider.custom(url).name,
            footer: "Part of the URL is hidden because it can contain a key.",
            isListed: isListed
        ) {
            Button("Delete RPC", systemImage: "trash", role: .destructive) { removal = url }
                .labelStyle(.warning)
                .lineLimit(1)
                .confirmation("Delete RPC?", action: "Delete", item: $removal, perform: actions.remove) { url in
                    CustomRPCDeletionMessage(url: url, isSelected: isSelected)
                }
        }
    }
}
