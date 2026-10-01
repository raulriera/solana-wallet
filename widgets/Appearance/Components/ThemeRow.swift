import SwiftUI

/// An inline theme choice with confirmed swipe deletion for custom packs.
struct ThemeRow: View {
    let entry: ThemeEntry
    let isSelected: Bool
    let palette: RenderedPalette
    let select: () -> Void
    let remove: (ThemeEntry) -> Void
    @State private var removal: ThemeEntry?

    var body: some View {
        ThemeChoiceRow(name: entry.name, isSelected: isSelected, palette: palette, select: select)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if entry.origin == .custom {
                    // Only the confirmation commits deletion, so keep the row visible while asking.
                    Button("Delete", systemImage: "trash") { removal = entry }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                        .tint(.red)
                }
            }
            .confirmationDialog("Delete Theme?", item: $removal) { approved in
                Button("Delete", role: .destructive) { remove(approved) }
            } message: { _ in
                Text("Are you sure you want to delete this theme?")
            }
    }
}
