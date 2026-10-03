import SwiftUI

/// One accessible theme choice with an independent SwiftUI update boundary.
struct ThemeChoiceRow: View {
    @Environment(\.palette) private var palette
    let themeID: UUID?
    /// The package's unchanged name, or `nil` for the localized inheritance choice.
    let name: String?
    let isSelected: Bool
    let scope: AppearancePreferences.Scope
    let actions: any ThemeActions

    var body: some View {
        Button(action: select) {
            HStack {
                if let name {
                    Text(name)
                } else {
                    Text("Use App Default")
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent).accessibilityHidden(true)
                }
            }
            .foregroundStyle(palette.primaryText)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Sends the choice through its window's workflow, preserving Original wallet overrides.
    private func select() {
        actions.select(scope == .application && themeID == OriginalAppearance.id ? nil : themeID, for: scope)
    }
}
