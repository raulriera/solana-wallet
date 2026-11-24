import SwiftUI

/// Shows a custom price server's masked URL and deletes the server after the person confirms.
struct PriceServerDetailsScreen: View {
    let url: URL
    /// Whether the server is still in the list.
    let isListed: Bool
    /// Whether the server is the price provider in use.
    let isSelected: Bool
    let actions: any PriceActions
    @State private var removal: URL?

    var body: some View {
        MaskedURLDetails(
            url: url,
            title: PriceSettings.Provider.custom(url).name,
            footer: "Part of the URL is hidden because it can contain a key.",
            isListed: isListed
        ) {
            Button("Delete Server", systemImage: "trash", role: .destructive) { removal = url }
                .labelStyle(.warning)
                .lineLimit(1)
                .confirmation("Delete Price Server?", action: "Delete", item: $removal, perform: actions.remove) { url in
                    PriceServerDeletionMessage(url: url, isSelected: isSelected)
                }
        }
    }
}
