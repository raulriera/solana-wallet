import SwiftUI

/// Gives every split view's sidebar the same preferred width, so sidebars match when people switch tabs.
struct SidebarColumnWidth: ViewModifier {
    /// Applies the shared sidebar width.
    /// - Parameter content: The content of a split view's sidebar column.
    /// - Returns: The sidebar content with the shared preferred width.
    func body(content: Content) -> some View {
        // Sidebars prefer 360 pt; people can drag them between 320 and 420 pt.
        content.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
    }
}

extension View {
    /// Sizes the sidebar column that contains this view like every other sidebar in the app.
    /// - Returns: The view with the shared sidebar width.
    func sidebarColumnWidth() -> some View {
        modifier(SidebarColumnWidth())
    }
}
