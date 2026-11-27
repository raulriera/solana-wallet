import SwiftUI

/// Gives a split view's sidebar column the app's shared width, an inline title, and the theme's sidebar color.
private struct SidebarColumn: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let sidebar = palette.sidebar
        content
            .navigationSplitViewColumnWidth(min: 320, ideal: 360)
            .toolbarTitleDisplayMode(.inline)
            .scrollContentBackground(sidebar == nil ? .automatic : .hidden)
            .background(sidebar ?? .clear)
    }
}

extension View {
    /// Gives the sidebar column that contains this view the app's shared width, an inline title, and the theme's sidebar color.
    ///
    /// - Returns: The view as a sidebar column, with the system sidebar when the theme has no sidebar color.
    func sidebarColumn() -> some View {
        modifier(SidebarColumn())
    }
}
