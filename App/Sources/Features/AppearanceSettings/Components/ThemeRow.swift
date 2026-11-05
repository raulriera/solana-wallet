import SwiftUI

/// A theme choice for the app, with swipe deletion for installed themes.
struct ThemeRow: View {
    let entry: ThemeEntry
    let isSelected: Bool
    let actions: any ThemeActions
    @State private var removal: ThemeEntry?

    var body: some View {
        Button(entry.name, action: select)
            .checked(isSelected)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if entry.origin == .custom {
                    SwipeDeleteButton(removal: $removal, item: entry)
                }
            }
            .confirmation("Delete Theme?", action: "Delete", item: $removal, perform: actions.remove) { approved in
                Text("\(approved.name) will be deleted from this device.",
                     comment: "The Delete Theme confirmation's message. The variable is the theme's name.")
            }
    }

    /// Selects the row's theme, or the original appearance.
    private func select() {
        actions.select(entry.id == OriginalAppearance.id ? nil : entry.id)
    }
}
