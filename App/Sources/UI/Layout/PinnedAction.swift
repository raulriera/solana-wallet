import SwiftUI

/// Pins a screen's single action to its bottom edge in a bar over the content's soft scroll edge.
private struct PinnedAction<Action: View>: ViewModifier {
    let inset: CGFloat
    let action: Action?

    /// Places the action in a bottom bar aligned with the content.
    /// - Parameter content: The scroll container the bar insets.
    /// - Returns: The container with the action pinned below it, or without a bar when there's no action.
    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                // Padding alone would keep an empty bar, so a screen without an action gets none.
                if let action {
                    action
                        .padding(.horizontal, inset)
                        .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
                }
            }
    }
}

extension View {
    /// Pins a single action to the bottom edge, below the scrolling content.
    /// - Parameters:
    ///   - inset: The horizontal inset that aligns the action with the content.
    ///   - action: The action, usually one button, or `nil` when the screen has none.
    /// - Returns: The view with the action pinned to its bottom edge.
    func pinnedAction<Action: View>(inset: CGFloat, @ViewBuilder _ action: () -> Action?) -> some View {
        modifier(PinnedAction(inset: inset, action: action()))
    }
}
