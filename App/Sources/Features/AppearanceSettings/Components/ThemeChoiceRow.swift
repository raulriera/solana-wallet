import SwiftUI

/// A button that selects one theme.
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
            if let name {
                Text(name)
            } else {
                Text("Use App Default")
            }
        }
        .buttonStyle(.choice(isSelected: isSelected))
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }

    /// Sends the choice through its window's workflow, preserving Original wallet overrides.
    private func select() {
        actions.select(scope == .application && themeID == OriginalAppearance.id ? nil : themeID, for: scope)
    }
}
