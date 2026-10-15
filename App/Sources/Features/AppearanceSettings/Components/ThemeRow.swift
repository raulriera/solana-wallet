import SwiftUI

/// An inline theme choice with confirmed swipe deletion for custom packs.
struct ThemeRow: View {
    let entry: ThemeEntry
    let isSelected: Bool
    let actions: any ThemeActions
    @State private var removal: ThemeEntry?

    var body: some View {
        ThemeChoiceRow(themeID: entry.id, name: entry.name, isSelected: isSelected, scope: .application,
                       actions: actions)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if entry.origin == .custom {
                    SwipeDeleteButton(removal: $removal, item: entry)
                }
            }
            .alert("Delete Theme?", item: $removal) { approved in
                Button("Delete", role: .destructive) { actions.remove(approved) }
                Button("Cancel", role: .cancel) {}
            } message: { approved in
                Text("\(approved.name) will be deleted from this device.",
                     comment: "The Delete Theme alert's message. The variable is the theme's name.")
            }
    }
}
