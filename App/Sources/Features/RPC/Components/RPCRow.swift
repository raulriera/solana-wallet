import SwiftUI

/// One provider choice, with a leading checkmark while it's in use, an info button when it has details, and swipe
/// deletion for a custom RPC.
struct RPCRow: View {
    let provider: RPCSettings.Provider
    let isSelected: Bool
    let actions: any RPCActions

    var body: some View {
        HStack {
            Button(provider.name) { actions.select(provider) }
                .checked(isSelected)

            if provider.hasDetails {
                Button(moreInfoAbout: provider.name) { actions.showDetails(for: provider) }
                    .buttonStyle(.moreInfo)
            }
        }
        .swipeDelete(provider.customURL, title: "Delete RPC?", perform: actions.remove) { url in
            CustomRPCDeletionMessage(url: url, isSelected: isSelected)
        }
    }
}
