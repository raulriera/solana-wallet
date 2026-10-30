import SwiftUI

/// Gives a split view's sidebar column the app's shared width.
struct SidebarColumnWidth: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
    }
}

extension View {
    /// Gives the sidebar column that contains this view the app's shared width.
    ///
    /// - Returns: The view with the shared sidebar width.
    func sidebarColumnWidth() -> some View {
        modifier(SidebarColumnWidth())
    }
}
