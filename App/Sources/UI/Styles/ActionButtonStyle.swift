import SwiftUI
import Themes

/// A full-width button style that adds theme colors and a border to a native style.
struct ActionButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette
    private let base: Base
    private let fill: Palette.Role
    private let content: Palette.Role

    /// Creates an action style.
    ///
    /// - Parameters:
    ///   - base: The native style.
    ///   - fill: The button's color.
    ///   - content: The color of the label on the button's color.
    fileprivate init(base: Base, fill: Palette.Role, content: Palette.Role) {
        self.base = base
        self.fill = fill
        self.content = content
    }

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .padding(.vertical, 6)
        }
        .buttonSizing(.flexible)
        .buttonStyle(base)
        .tint(palette[fill])
        .foregroundStyle(palette[content])
        .themedButtonBorder()
    }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedProminentButtonStyle> {
    /// A prominent action in the theme's primary colors.
    static var primary: Self { Self(base: .borderedProminent, fill: .primary, content: .onPrimary) }

    /// A less prominent action in the theme's secondary colors.
    static var secondary: Self { Self(base: .borderedProminent, fill: .secondary, content: .onSecondary) }

    /// A prominent destructive action in the theme's destructive colors.
    static var destructive: Self { Self(base: .borderedProminent, fill: .destructive, content: .onDestructive) }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<GlassProminentButtonStyle> {
    /// A prominent glass action in the theme's primary colors.
    static var glassPrimary: Self { Self(base: .glassProminent, fill: .primary, content: .onPrimary) }
}
