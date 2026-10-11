import SwiftUI

/// One provider choice, with a leading checkmark while it's in use and an info button when it has details.
struct ProviderRow: View {
    @Environment(\.palette) private var palette
    let provider: ProviderSettings.Provider
    let isSelected: Bool
    let actions: any ProviderActions

    var body: some View {
        HStack {
            Button { actions.select(provider) } label: {
                HStack {
                    // The hidden checkmark keeps its space, so every name starts at the same place.
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.accent)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                    Text(provider.name)
                    Spacer()
                }
                .foregroundStyle(palette.primaryText)
                .contentShape(.rect)
            }
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if provider.hasDetails {
                Button("More Info", systemImage: "info.circle") { actions.showDetails(for: provider) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(palette.accent)
                    // A borderless button handles its own taps, so the rest of the row stays the choice.
                    .buttonStyle(.borderless)
            }
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }
}
