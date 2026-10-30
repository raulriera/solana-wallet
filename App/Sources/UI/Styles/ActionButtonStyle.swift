import SwiftUI

/// A large, full-width button style that adds theme colors to a native style.
struct ActionButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette
    private let base: Base
    private let tint: ActionColor
    private let foreground: ActionColor

    /// Creates an action style.
    ///
    /// - Parameters:
    ///   - base: The native style.
    ///   - tint: The button's color.
    ///   - foreground: The label's color.
    fileprivate init(base: Base, tint: ActionColor, foreground: ActionColor) {
        self.base = base
        self.tint = tint
        self.foreground = foreground
    }

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
        .buttonSizing(.flexible)
        .buttonStyle(base)
        .controlSize(.large)
        .tint(tint.resolved(in: palette))
        .foregroundStyle(foreground.resolved(in: palette))
    }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedProminentButtonStyle> {
    /// A prominent action in the window's text color.
    static var primary: Self { Self(base: .borderedProminent, tint: .palette(.primaryText), foreground: .palette(.background)) }

    /// A prominent destructive action in red.
    static var destructive: Self { Self(base: .borderedProminent, tint: .fixed(.red), foreground: .fixed(.white)) }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<GlassProminentButtonStyle> {
    /// A prominent glass action in the window's accent color.
    static var glassPrimary: Self {
        Self(base: .glassProminent, tint: .palette(.accent), foreground: .palette(.onAccent))
    }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedButtonStyle> {
    /// A bordered action with a label in the window's text color.
    static var secondary: Self { Self(base: .bordered, tint: .palette(.primaryText), foreground: .palette(.primaryText)) }
}

/// An action's color: a palette role or a fixed color.
fileprivate enum ActionColor {
    case palette(PaletteRole)
    case fixed(Color)

    /// Returns the color in a palette.
    ///
    /// - Parameter palette: The window's palette.
    /// - Returns: The role's color in the palette, or the fixed color.
    func resolved(in palette: RenderedPalette) -> Color {
        switch self {
        case .palette(let role): role.color(in: palette)
        case .fixed(let color): color
        }
    }
}
