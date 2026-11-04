import SwiftUI

/// A large, full-width button style that adds theme colors to a native style.
struct ActionButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette
    private let base: Base
    private let fill: PaletteRole
    private let content: PaletteRole

    /// Creates an action style.
    ///
    /// - Parameters:
    ///   - base: The native style.
    ///   - fill: The button's color.
    ///   - content: The color of the label on the button's color.
    fileprivate init(base: Base, fill: PaletteRole, content: PaletteRole) {
        self.base = base
        self.fill = fill
        self.content = content
    }

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
        .buttonSizing(.flexible)
        .buttonStyle(base)
        .controlSize(.large)
        .tint(fill.color(in: palette))
        .foregroundStyle(content.color(in: palette))
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
