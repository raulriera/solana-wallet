import SwiftUI

/// One provider choice, with a leading checkmark while it's in use and an info button when it has details.
struct ProviderRow: View {
    @Environment(\.palette) private var palette
    let provider: ProviderSettings.Provider
    let isSelected: Bool
    let actions: any ProviderActions

    var body: some View {
        HStack {
            // A leading checkmark leaves the trailing edge to the info button.
            Button(provider.name) { actions.select(provider) }
                .buttonStyle(.choice(isSelected: isSelected, placement: .leading))

            if provider.hasDetails {
                Button("More Info", systemImage: "info.circle") { actions.showDetails(for: provider) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(palette.accent)
                    // A borderless button handles its own taps, so the rest of the row stays the choice.
                    .buttonStyle(.borderless)
            }
        }
    }
}
