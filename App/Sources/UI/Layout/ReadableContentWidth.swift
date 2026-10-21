import SwiftUI

/// Centers a form's rows at a readable width in wide containers, as Settings does on iPad.
#warning("This doesn't belong in 'Layout'")
private struct ReadableContentWidth: ViewModifier {
    @State private var margins: EdgeInsets?

    /// Narrows wide content and leaves the system margins everywhere else.
    /// - Parameter content: The form to measure and inset.
    /// - Returns: The form with readable margins in wide containers.
    func body(content: Content) -> some View {
        content
            // Nil margins keep the system's.
            .contentMargins(.leading, margins?.leading, for: .scrollContent)
            .contentMargins(.trailing, margins?.trailing, for: .scrollContent)
            .onGeometryChange(for: EdgeInsets?.self) { geometry in
                let inset = (geometry.size.width - LayoutMetrics.readableWidth) / 2
                // Only insets wider than the system's margins take over, so the form doesn't jump.
                let system = geometry.contentMargins(for: .container, edges: .horizontal)
                guard inset > max(system.leading, system.trailing) else { return nil }
                // A form measures margins from the edges of the safe area it extends into.
                return EdgeInsets(top: 0, leading: inset + geometry.safeAreaInsets.leading,
                                  bottom: 0, trailing: inset + geometry.safeAreaInsets.trailing)
            } action: { newMargins in
                margins = newMargins
            }
    }
}

extension View {
    /// Centers a form's rows at a readable width in wide containers.
    /// - Returns: The form with readable margins in wide containers.
    func readableContentWidth() -> some View {
        modifier(ReadableContentWidth())
    }
}
