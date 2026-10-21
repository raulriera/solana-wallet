import SwiftUI

/// The typed amount in large rounded digits that roll as they change and shake when a key is rejected, drawn in
/// the window's ``KeypadStyle``.
///
/// Like a text field, the amount takes keyboard focus, so a hardware keyboard types without a tap first.
struct AmountDisplay: View {
    @Environment(\.palette) private var palette
    @Environment(\.keypadStyle) private var style
    @ScaledMetric(relativeTo: .largeTitle) private var size = 72.0
    @FocusState private var isFocused: Bool
    /// The formatted amount.
    let text: String
    /// Counts rejected keys; each change shakes the amount.
    let rejectionCount: Int

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .foregroundStyle(fill)
            // Key presses animate the change, so the digits roll into place.
            .contentTransition(.numericText())
            .environment(\.contentTransitionAddsDrawingGroup, true)
            .keyframeAnimator(initialValue: 0.0, trigger: rejectionCount) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-12, duration: 0.05)
                    LinearKeyframe(10, duration: 0.08)
                    LinearKeyframe(-6, duration: 0.07)
                    LinearKeyframe(3, duration: 0.06)
                    LinearKeyframe(0, duration: 0.05)
                }
            }
            .accessibilityLabel("Amount")
            .accessibilityValue(text)
            .focusable(interactions: .edit)
            .focused($isFocused)
            // Choosing another tab or screen moves focus away, and default focus doesn't take it back, so the amount
            // takes it when it appears.
            .onAppear { isFocused = true }
    }

    /// The digits' fill: a brushed-metal sheen from a light at the top leading corner, or the plain text color.
    private var fill: AnyShapeStyle {
        switch style.amountLook {
        case .chrome:
            AnyShapeStyle(LinearGradient(colors: [palette.primaryText, palette.secondaryText, palette.primaryText],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
        case .plain:
            AnyShapeStyle(palette.primaryText)
        }
    }
}
