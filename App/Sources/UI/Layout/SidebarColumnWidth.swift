import SwiftUI

/// Gives every split view's sidebar the same preferred width, so sidebars match when people switch tabs.
struct SidebarColumnWidth: ViewModifier {
    /// Applies the shared sidebar width.
    /// - Parameter content: The content of a split view's sidebar column.
    /// - Returns: The sidebar content with the shared preferred width.
    func body(content: Content) -> some View {
        content.navigationSplitViewColumnWidth(min: 280, ideal: 320)
    }
}

extension View {
    /// Sizes the sidebar column that contains this view like every other sidebar in the app.
    /// - Returns: The view with the shared sidebar width.
    func sidebarColumnWidth() -> some View {
        modifier(SidebarColumnWidth())
    }
}
