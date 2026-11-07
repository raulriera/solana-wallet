import SwiftUI

/// One price provider choice, with a leading checkmark while it's in use, and an info button and swipe deletion for a
/// custom server.
struct PriceProviderRow: View {
    let provider: PriceSettings.Provider
    let isSelected: Bool
    let actions: any PriceActions

    var body: some View {
        HStack {
            Button(provider.name) { actions.select(provider) }
                .checked(isSelected)

            if let url = provider.customURL {
                Button(moreInfoAbout: provider.name) { actions.showDetails(of: url) }
                    .buttonStyle(.moreInfo)
            }
        }
        .swipeDelete(provider.customURL, title: "Delete Price Server?", perform: actions.remove) { url in
            PriceServerDeletionMessage(url: url, isSelected: isSelected)
        }
    }
}
