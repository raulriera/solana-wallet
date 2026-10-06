import SwiftUI

/// Calculates one readable inset for scroll content and a separately pinned action.
struct ReadableContentMargins: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var safeAreaInsets = EdgeInsets()
    @Binding var inset: CGFloat

    /// Applies matching content and action margins inside the horizontal safe area.
    /// - Parameter content: The full-width scroll container to measure and inset.
    /// - Returns: The container with independently inset scroll content.
    func body(content: Content) -> some View {
        let usesReadableWidth = horizontalSizeClass == .regular

        content
            // Form extends beyond the proposed safe area; explicit content margins replace its native insets.
            .contentMargins(.leading, inset + safeAreaInsets.leading, for: .scrollContent)
            .contentMargins(.trailing, inset + safeAreaInsets.trailing, for: .scrollContent)
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: {
                safeAreaInsets = $0
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                // Wide containers keep content at most 896 pt wide, with at least 20 pt on each side.
                usesReadableWidth ? max(20, (geometry.size.width - 896) / 2) : LayoutMetrics.contentMargin
            } action: { newInset in
                inset = newInset
            }
    }
}

extension View {
    /// Insets scroll content and shares the calculated inset with pinned actions.
    /// - Parameter inset: The calculated horizontal inset for other content to reuse.
    /// - Returns: The view with readable scroll-content margins.
    func readableContentMargins(inset: Binding<CGFloat>) -> some View {
        modifier(ReadableContentMargins(inset: inset))
    }
}
