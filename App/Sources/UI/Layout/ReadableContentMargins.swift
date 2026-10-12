import SwiftUI

/// Calculates one readable inset for scroll content and a separately pinned action.
struct ReadableContentMargins: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var safeAreaInsets = EdgeInsets()
    @Binding var inset: CGFloat
    let addsSafeArea: Bool

    /// Applies matching content and action margins inside the horizontal safe area.
    /// - Parameter content: The full-width scroll container to measure and inset.
    /// - Returns: The container with independently inset scroll content.
    func body(content: Content) -> some View {
        let usesReadableWidth = horizontalSizeClass == .regular
        let safeArea = addsSafeArea ? safeAreaInsets : EdgeInsets()

        content
            // Form keeps rows out of the safe area but doesn't add it to explicit margins; ScrollView adds it.
            .contentMargins(.leading, inset + safeArea.leading, for: .scrollContent)
            .contentMargins(.trailing, inset + safeArea.trailing, for: .scrollContent)
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
    /// - Parameters:
    ///   - inset: The calculated horizontal inset for other content to reuse.
    ///   - addsSafeArea: Whether the margins include the horizontal safe area. A `Form` needs it;
    ///     pass `false` for a `ScrollView`, which adds the safe area to its margins itself.
    /// - Returns: The view with readable scroll-content margins.
    func readableContentMargins(inset: Binding<CGFloat>, addsSafeArea: Bool = true) -> some View {
        modifier(ReadableContentMargins(inset: inset, addsSafeArea: addsSafeArea))
    }

    /// Insets scroll content on a screen that shares the calculated inset with nothing else.
    /// - Parameter addsSafeArea: Whether the margins include the horizontal safe area. A `Form` needs it;
    ///   pass `false` for a `ScrollView`, which adds the safe area to its margins itself.
    /// - Returns: The view with readable scroll-content margins.
    func readableContentMargins(addsSafeArea: Bool = true) -> some View {
        modifier(OwnedReadableContentMargins(addsSafeArea: addsSafeArea))
    }
}

/// Keeps the calculated inset for content that doesn't share it with a pinned action.
private struct OwnedReadableContentMargins: ViewModifier {
    @State private var inset = LayoutMetrics.contentMargin
    let addsSafeArea: Bool

    /// Applies readable margins with an inset this modifier owns.
    /// - Parameter content: The full-width scroll container to measure and inset.
    /// - Returns: The container with readable scroll-content margins.
    func body(content: Content) -> some View {
        content.readableContentMargins(inset: $inset, addsSafeArea: addsSafeArea)
    }
}
