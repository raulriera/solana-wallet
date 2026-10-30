import SwiftUI

/// Shows a row's swipe action as a white symbol on a colored button.
private struct SwipeActionTint: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .foregroundStyle(.white)
            .tint(color)
    }
}

extension View {
    /// Shows a row's swipe action as a white symbol on a colored button.
    ///
    /// - Parameter color: The button's color.
    /// - Returns: The swipe action's button with its symbol in white on the color.
    func swipeActionTint(_ color: Color) -> some View {
        modifier(SwipeActionTint(color: color))
    }
}
