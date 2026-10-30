import SwiftUI

/// Centers a form's rows at a readable width in wide containers.
private struct ReadableContentWidth: ViewModifier {
    @State private var margins: EdgeInsets?

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, margins?.leading, for: .scrollContent)
            .contentMargins(.trailing, margins?.trailing, for: .scrollContent)
            .onGeometryChange(for: EdgeInsets?.self) { geometry in
                let inset = (geometry.size.width - LayoutMetrics.readableWidth) / 2
                let system = geometry.contentMargins(for: .container, edges: .horizontal)
                guard inset > max(system.leading, system.trailing) else { return nil }
                return EdgeInsets(top: 0, leading: inset + geometry.safeAreaInsets.leading,
                                  bottom: 0, trailing: inset + geometry.safeAreaInsets.trailing)
            } action: { newMargins in
                margins = newMargins
            }
    }
}

extension View {
    /// Centers a form's rows at a readable width in wide containers.
    ///
    /// - Returns: The form with readable margins in wide containers.
    func readableContentWidth() -> some View {
        modifier(ReadableContentWidth())
    }
}
