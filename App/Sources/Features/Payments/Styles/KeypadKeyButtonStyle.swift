import SwiftUI

/// A round keypad key that fills the space it's offered up to a comfortable size, drawn as the window's
/// ``KeypadStyle`` asks: on interactive glass, on a filled circle, or as the digit alone.
struct KeypadKeyButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.keypadStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    /// Whether the key takes the style's background; the decimal point and delete show only their symbols.
    let hasBackground: Bool

    /// Draws the key's label centered on its background, which responds while pressed.
    /// - Parameter configuration: The key's label and pressed state.
    /// - Returns: The styled key.
    func makeBody(configuration: Configuration) -> some View {
        let background = hasBackground ? style.keyBackground : .none
        configuration.label
            .font(.largeTitle)
            .minimumScaleFactor(0.5)
            // Keys stop growing with the text size, so large text sizes show the key in the large content viewer.
            .accessibilityShowsLargeContentViewer()
            // Keys act as keyboard keys, so VoiceOver's typing style applies, as on system keypads.
            .accessibilityAddTraits(.isKeyboardKey)
            .foregroundStyle(style.keyText.color(in: palette).opacity(isEnabled ? 1 : 0.4))
            // Keys without glass dim while pressed; glass answers the touch itself.
            .opacity(configuration.isPressed && background != .glass ? 0.6 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(background == .filled ? style.keyFill.color(in: palette) : .clear, in: .circle)
            .contentShape(.circle)
            .glassEffect(background == .glass ? .regular.interactive() : .identity, in: .circle)
            // Keys stop growing at a large circle, so wide spaces don't stretch them.
            .frame(maxWidth: 110, maxHeight: 110)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KeypadKeyButtonStyle {
    /// A digit key, on the keypad style's background.
    static var keypadKey: Self { Self(hasBackground: true) }

    /// A key that shows only its symbol, such as the decimal point or delete.
    static var keypadSymbolKey: Self { Self(hasBackground: false) }
}
