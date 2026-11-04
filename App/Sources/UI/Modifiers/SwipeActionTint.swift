import SwiftUI

/// Shows a row's swipe action as a symbol on a colored button.
private struct SwipeActionTint: ViewModifier {
    let color: Color
    let symbolColor: Color

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .foregroundStyle(symbolColor)
            .tint(color)
    }
}

extension View {
    /// Shows a row's swipe action as a symbol on a colored button.
    ///
    /// - Parameters:
    ///   - color: The button's color.
    ///   - symbolColor: The color of the symbol on the button.
    /// - Returns: The swipe action's button with its symbol on the color.
    func swipeActionTint(_ color: Color, symbolColor: Color = .white) -> some View {
        modifier(SwipeActionTint(color: color, symbolColor: symbolColor))
    }
}
