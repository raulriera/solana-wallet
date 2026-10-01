import SwiftUI

/// Presents committed selection data without observing the full package workflow.
struct ThemeChooser: View {
    let entries: [ThemeEntry]
    let scope: AppearancePreferences.Scope
    let selection: UUID?
    let palette: RenderedPalette
    let actions: any ThemeActions

    private var selectedID: UUID? { scope == .application ? selection ?? OriginalAppearance.id : selection }

    private var title: String { scope == .application ? "App Theme" : "Wallet Theme" }

    var body: some View {
        List {
            if case .wallet = scope {
                ThemeChoiceRow(themeID: nil, name: "Use App Default", isSelected: selectedID == nil, scope: scope,
                               primaryText: palette.primaryText, accent: palette.accent,
                               surface: palette.surface, separator: palette.separator, actions: actions)
            }
            ForEach(entries) { entry in
                ThemeChoiceRow(themeID: entry.id, name: entry.name, isSelected: selectedID == entry.id, scope: scope,
                               primaryText: palette.primaryText, accent: palette.accent,
                               surface: palette.surface, separator: palette.separator, actions: actions)
            }
        }
        .animation(.default, value: entries.map(\.id))
        .navigationTitle(title)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }
}
