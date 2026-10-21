import SwiftUI

/// Draws a view's symbols on when it appears and replaces them when they change.
#warning("This doesn't belong in 'Styles'")
private struct DrawOnAppear: ViewModifier {
    @State private var isDrawn = false

    /// Hides the symbols until the view appears, then draws them on once.
    /// - Parameter content: The view whose symbol images animate.
    /// - Returns: The view with its symbols drawn on when it appears and replaced when they change.
    func body(content: Content) -> some View {
        content
            // Symbols without draw data fade in instead.
            .symbolEffect(.drawOn, isActive: !isDrawn)
            // A later symbol, such as a new error's, swaps in place instead of drawing on again.
            .contentTransition(.symbolEffect(.replace))
            .onAppear { isDrawn = true }
    }
}

extension View {
    /// Draws this view's symbols on once when it appears, and replaces them when they change.
    /// - Returns: The view with its symbols drawn on when it appears.
    func drawOnAppear() -> some View {
        modifier(DrawOnAppear())
    }
}
