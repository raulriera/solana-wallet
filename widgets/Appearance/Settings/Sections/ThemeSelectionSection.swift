import SwiftUI

/// Inline choices for the shared application theme, including custom-theme deletion.
struct ThemeSelectionSection: View {
    let entries: [ThemeEntry]
    let selection: UUID
    let palette: RenderedPalette
    let select: (UUID) -> Void
    let remove: (ThemeEntry) -> Void

    var body: some View {
        Section("App Theme") {
            ForEach(entries) { entry in
                ThemeRow(entry: entry, isSelected: selection == entry.id, palette: palette) {
                    select(entry.id)
                } remove: { approved in
                    remove(approved)
                }
            }
        }
    }
}
