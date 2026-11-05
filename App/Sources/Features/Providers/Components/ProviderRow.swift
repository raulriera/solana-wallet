import SwiftUI

/// One provider choice, with a leading checkmark while it's in use and an info button when it has details.
struct ProviderRow: View {
    let provider: ProviderSettings.Provider
    let isSelected: Bool
    let actions: any ProviderActions

    var body: some View {
        HStack {
            Button(provider.name) { actions.select(provider) }
                .checked(isSelected)

            if provider.hasDetails {
                Button("More Info", systemImage: "info.circle") { actions.showDetails(for: provider) }
                    .buttonStyle(.moreInfo)
            }
        }
    }
}
