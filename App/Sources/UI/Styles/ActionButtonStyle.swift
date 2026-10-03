import SwiftUI

/// Applies shared action sizing and theme colors around a native button style.
struct ActionButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette
    private let base: Base
    private let foreground: KeyPath<RenderedPalette, Color>

    /// Pairs a native treatment with its semantic label color.
    /// - Parameters:
    ///   - base: The native style responsible for appearance and interaction.
    ///   - foreground: The label's color role in the current window's palette.
    fileprivate init(base: Base, foreground: KeyPath<RenderedPalette, Color>) {
        self.base = base
        self.foreground = foreground
    }

    /// Styles the label while delegating activation and feedback to a native button.
    /// - Parameter configuration: The original button's label, role, and action.
    /// - Returns: A full-width action using the current window's appearance.
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.actionLabelMinimumHeight)
        }
        .buttonStyle(base)
        .controlSize(.large)
        .tint(palette.primaryText)
        .foregroundStyle(palette[keyPath: foreground])
    }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedProminentButtonStyle> {
    /// A prominent action with the window's contrasting background color for its label.
    static var primary: Self { Self(base: .borderedProminent, foreground: \.background) }
}

extension PrimitiveButtonStyle where Self == ActionButtonStyle<BorderedButtonStyle> {
    /// A secondary action with the window's primary text color for its label.
    static var secondary: Self { Self(base: .bordered, foreground: \.primaryText) }
}
