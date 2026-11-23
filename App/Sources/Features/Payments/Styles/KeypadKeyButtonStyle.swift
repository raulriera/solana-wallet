import SwiftUI

/// A button style for a round keypad key drawn in the ``KeypadStyle``.
struct KeypadKeyButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.keypadStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    /// Whether the key shows the style's background.
    let hasBackground: Bool

    func makeBody(configuration: Configuration) -> some View {
        let background = hasBackground ? style.keyBackground : .none
        configuration.label
            .font(.largeTitle)
            .minimumScaleFactor(0.5)
            .accessibilityShowsLargeContentViewer()
            .accessibilityAddTraits(.isKeyboardKey)
            .foregroundStyle(Color.primary.opacity(isEnabled ? 1 : 0.4))
            .opacity(configuration.isPressed && background != .glass ? 0.6 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(background == .filled ? palette[style.keyFill] : .clear, in: .circle)
            .contentShape(.circle)
            .glassEffect(background == .glass ? .regular.interactive() : .identity, in: .circle)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KeypadKeyButtonStyle {
    static var keypadKey: Self { Self(hasBackground: true) }

    /// A key that shows only its symbol, without a background.
    static var keypadSymbolKey: Self { Self(hasBackground: false) }
}
