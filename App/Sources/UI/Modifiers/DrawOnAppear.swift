import SwiftUI

/// Draws a view's symbols on when it appears and replaces them when they change.
private struct DrawOnAppear: ViewModifier {
    @State private var isDrawn = false

    func body(content: Content) -> some View {
        content
            .symbolEffect(.drawOn, isActive: !isDrawn)
            .contentTransition(.symbolEffect(.replace))
            .onAppear { isDrawn = true }
    }
}

extension View {
    /// Draws this view's symbols on once when it appears, and replaces them when they change.
    ///
    /// - Returns: The view with its symbols drawn on when it appears.
    func drawOnAppear() -> some View {
        modifier(DrawOnAppear())
    }
}
