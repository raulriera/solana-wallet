import SwiftUI

/// Calculates one readable inset for scroll content and a separately pinned action.
struct ReadableContentMargins: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var inset: CGFloat

    /// Applies horizontal content margins while preserving native margins at full width.
    /// - Parameter content: The full-width scroll container to measure and inset.
    /// - Returns: The container with independently inset scroll content.
    func body(content: Content) -> some View {
        let usesReadableWidth = horizontalSizeClass == .regular

        content
            .contentMargins(.horizontal, inset > 0 ? inset : nil, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { geometry in
                // A sixth on each side leaves two thirds for content.
                usesReadableWidth ? geometry.size.width / 6 : 0
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
