import SwiftUI

/// Chooses a wallet's theme or Use App Default.
struct ThemeChooser: View {
    @Environment(\.palette) private var palette
    let entries: [ThemeEntry]
    let entryIDs: [UUID]
    let scope: AppearancePreferences.Scope
    let selection: UUID?
    let actions: any ThemeActions

    private var selectedID: UUID? { scope == .application ? selection ?? OriginalAppearance.id : selection }

    private var title: LocalizedStringKey { scope == .application ? "App Theme" : "Wallet Theme" }

    var body: some View {
        List {
            if case .wallet = scope {
                ThemeChoiceRow(themeID: nil, name: nil, isSelected: selectedID == nil, scope: scope,
                               actions: actions)
            }
            ForEach(entries) { entry in
                ThemeChoiceRow(themeID: entry.id, name: entry.name, isSelected: selectedID == entry.id, scope: scope,
                               actions: actions)
            }
        }
        .animation(.default, value: entryIDs)
        .navigationTitle(title)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }
}
