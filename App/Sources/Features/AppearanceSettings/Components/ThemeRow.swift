import SwiftUI

/// A theme choice for the app, with swipe deletion for installed themes.
struct ThemeRow: View {
    let entry: ThemeEntry
    let isSelected: Bool
    let actions: any ThemeActions

    var body: some View {
        Button(entry.name, action: select)
            .checked(isSelected)
            .swipeDelete(entry.origin == .custom ? entry : nil, title: "Delete Theme?",
                         perform: actions.remove) { approved in
                Text("\(approved.name) will be deleted from this device.",
                     comment: "The Delete Theme confirmation's message. The variable is the theme's name.")
            }
    }

    /// Selects the row's theme, or the original appearance.
    private func select() {
        actions.select(entry.id == OriginalAppearance.id ? nil : entry.id)
    }
}
