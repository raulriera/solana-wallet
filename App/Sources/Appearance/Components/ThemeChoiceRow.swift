import SwiftUI

/// One accessible theme choice with an independent SwiftUI update boundary.
struct ThemeChoiceRow: View {
    let themeID: UUID?
    let name: String
    let isSelected: Bool
    let scope: AppearancePreferences.Scope
    let primaryText: Color
    let accent: Color
    let surface: Color
    let separator: Color
    let actions: any ThemeActions

    var body: some View {
        Button(action: select) {
            HStack {
                Text(name).foregroundStyle(primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(accent).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .listRowBackground(surface)
        .listRowSeparatorTint(separator)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Sends the choice through its window's workflow, preserving Original wallet overrides.
    private func select() {
        actions.select(scope == .application && themeID == OriginalAppearance.id ? nil : themeID, for: scope)
    }
}
