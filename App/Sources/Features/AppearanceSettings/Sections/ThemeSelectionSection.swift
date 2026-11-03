import SwiftUI

/// A section that lists the app's theme choices.
struct ThemeSelectionSection: View {
    @Environment(\.palette) private var palette
    let entries: [ThemeEntry]
    let selection: UUID
    let actions: any ThemeActions

    var body: some View {
        Section("App Theme") {
            ForEach(entries) { entry in
                ThemeRow(entry: entry, isSelected: selection == entry.id, actions: actions)
            }
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }
}
