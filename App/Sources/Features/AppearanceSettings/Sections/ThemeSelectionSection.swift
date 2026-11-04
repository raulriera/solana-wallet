import SwiftUI

/// A section that lists the app's theme choices.
struct ThemeSelectionSection: View {
    let entries: [ThemeEntry]
    let selection: UUID
    let actions: any ThemeActions

    var body: some View {
        Section("App Theme") {
            ForEach(entries) { entry in
                ThemeRow(entry: entry, isSelected: selection == entry.id, actions: actions)
            }
        }
    }
}
