import SwiftUI

/// Gives a button a capsule shape and outlines it in the theme's border color.
private struct ThemedButtonBorder: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .buttonBorderShape(.capsule)
            .overlay {
                Capsule().strokeBorder(palette.border.opacity(isEnabled ? 1 : 0.3)).allowsHitTesting(false)
            }
    }
}

extension View {
    /// Gives this button a capsule shape and outlines it in the theme's border color.
    ///
    /// - Returns: A capsule button outlined in the theme's border color.
    func themedButtonBorder() -> some View {
        modifier(ThemedButtonBorder())
    }
}
