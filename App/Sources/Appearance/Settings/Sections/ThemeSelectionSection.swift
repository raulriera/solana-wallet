import SwiftUI

/// Inline choices for the shared application theme, including custom-theme deletion.
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
