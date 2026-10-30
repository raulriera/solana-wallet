import SwiftUI

/// The typed amount in large rounded digits that shake when a key is rejected.
struct AmountDisplay: View {
    @Environment(\.palette) private var palette
    @Environment(\.keypadStyle) private var style
    @ScaledMetric(relativeTo: .largeTitle) private var size = 72.0
    @FocusState private var isFocused: Bool
    /// The formatted amount.
    let text: String
    let rejectionCount: Int

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .foregroundStyle(palette.background)
            .contentTransition(.numericText())
            .environment(\.contentTransitionAddsDrawingGroup, true)
            .accessibilityLabel("Amount")
            .accessibilityValue(text)
            .focusable(interactions: .edit)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .overlay {
                Rectangle()
                    .fill(fill)
                    .scaleEffect(2)
                    .blendMode(.sourceAtop)
                    .allowsHitTesting(false)
            }
            .compositingGroup()
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
    }

    /// The digits' fill, a metallic gradient or the plain text color.
    private var fill: AnyShapeStyle {
        switch style.amountLook {
        case .chrome:
            AnyShapeStyle(LinearGradient(colors: [palette.primaryText, palette.secondaryText, palette.primaryText],
                                         startPoint: UnitPoint(x: 0.25, y: 0.25),
                                         endPoint: UnitPoint(x: 0.75, y: 0.75)))
        case .plain:
            AnyShapeStyle(palette.primaryText)
        }
    }
}
