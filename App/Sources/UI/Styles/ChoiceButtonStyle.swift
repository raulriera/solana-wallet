import SwiftUI

/// Shows a list choice's name with a trailing checkmark while it's selected, around a native list button.
struct ChoiceButtonStyle: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette
    private let isSelected: Bool

    /// Marks whether the choice is the selected one.
    /// - Parameter isSelected: Whether the choice is selected, which shows the checkmark.
    fileprivate init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    /// Lays out the name and checkmark while delegating activation and feedback to a native button.
    /// - Parameter configuration: The original button's label, role, and action.
    /// - Returns: A native button that shows the name in the window's primary text color and reports its selection to
    ///   VoiceOver.
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            HStack {
                configuration.label
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent).accessibilityHidden(true)
                }
            }
            .foregroundStyle(palette.primaryText)
            .contentShape(.rect)
        }
        // The automatic style keeps a list row's native button behavior, such as its row-wide tap area.
        .buttonStyle(.automatic)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension PrimitiveButtonStyle where Self == ChoiceButtonStyle {
    /// A list choice that shows its name, with a trailing checkmark while it's selected.
    /// - Parameter isSelected: Whether the choice is selected.
    /// - Returns: The choice style.
    static func choice(isSelected: Bool) -> Self {
        Self(isSelected: isSelected)
    }
}
