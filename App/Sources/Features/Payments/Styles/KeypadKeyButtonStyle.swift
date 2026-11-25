import SwiftUI

/// A button style for a round keypad key.
struct KeypadKeyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isBordered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.largeTitle)
            .minimumScaleFactor(0.5)
            .accessibilityShowsLargeContentViewer()
            .accessibilityAddTraits(.isKeyboardKey)
            .foregroundStyle(Color.primary.opacity(isEnabled ? 1 : 0.4))
            .opacity(configuration.isPressed && !isBordered ? 0.6 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(.circle)
            .glassEffect(isBordered ? .regular.interactive() : .identity, in: .circle)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KeypadKeyButtonStyle {
    static var keypadKey: Self { Self(isBordered: true) }

    /// A borderless key that shows only its symbol.
    static var keypadSymbolKey: Self { Self(isBordered: false) }
}
