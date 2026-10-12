import SwiftUI

/// Applies shared action sizing and theme colors around a native button style.
struct ActionButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette
    private let base: Base
    private let tint: ActionColor
    private let foreground: ActionColor
    private let isPending: Bool

    /// Pairs a native treatment with its button and label colors.
    /// - Parameters:
    ///   - base: The native style responsible for appearance and interaction.
    ///   - tint: The button's color.
    ///   - foreground: The label's color.
    ///   - isPending: Whether the action's work is running, so a spinner takes the title's place.
    fileprivate init(base: Base, tint: ActionColor, foreground: ActionColor, isPending: Bool = false) {
        self.base = base
        self.tint = tint
        self.foreground = foreground
        self.isPending = isPending
    }

    /// Styles the label while delegating activation and feedback to a native button.
    /// - Parameter configuration: The original button's label, role, and action.
    /// - Returns: A full-width action using the current window's appearance.
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                // A clear title keeps the button's size, and VoiceOver still reads it, while the spinner shows;
                // white keeps the native style's colors, including its disabled look.
                .colorMultiply(isPending ? .clear : .white)
                .overlay {
                    // The large controls would make the spinner taller than the title.
                    if isPending { ProgressView().controlSize(.regular) }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(base)
        .controlSize(.large)
        .tint(tint.resolved(in: palette))
        .foregroundStyle(foreground.resolved(in: palette))
    }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedProminentButtonStyle> {
    /// A prominent action with the window's contrasting background color for its label.
    static var primary: Self { .primary(isPending: false) }

    /// A prominent action that shows a spinner in place of its title while its work runs.
    /// - Parameter isPending: Whether the action's work is running.
    /// - Returns: The prominent action style.
    static func primary(isPending: Bool) -> Self {
        Self(base: .borderedProminent, tint: .palette(\.primaryText), foreground: .palette(\.background),
             isPending: isPending)
    }

    /// A prominent destructive action in the system's red, which no theme replaces.
    static var destructive: Self { Self(base: .borderedProminent, tint: .fixed(.red), foreground: .fixed(.white)) }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedButtonStyle> {
    /// A secondary action with the window's primary text color for its label.
    static var secondary: Self { Self(base: .bordered, tint: .palette(\.primaryText), foreground: .palette(\.primaryText)) }
}

/// A color an action takes from the window's palette, or a fixed system color that no theme replaces.
fileprivate enum ActionColor {
    case palette(KeyPath<RenderedPalette, Color>)
    case fixed(Color)

    /// Resolves the color for the current window.
    /// - Parameter palette: The window's palette.
    /// - Returns: The palette's color for this role, or the fixed color.
    func resolved(in palette: RenderedPalette) -> Color {
        switch self {
        case .palette(let role): palette[keyPath: role]
        case .fixed(let color): color
        }
    }
}
