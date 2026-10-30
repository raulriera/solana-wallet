import SwiftUI

/// A row that selects a theme for the app or a wallet.
struct ThemeChoiceRow: View {
    @Environment(\.palette) private var palette
    /// The theme, or `nil` for the app default.
    let themeID: UUID?
    /// The theme's name, or `nil` for the app default.
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

    /// Selects the row's theme for its scope.
    private func select() {
        actions.select(scope == .application && themeID == OriginalAppearance.id ? nil : themeID, for: scope)
    }
}
