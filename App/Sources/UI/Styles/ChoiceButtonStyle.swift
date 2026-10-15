import SwiftUI

/// Shows a list choice's name with a checkmark while it's selected, around a native list button.
struct ChoiceButtonStyle: PrimitiveButtonStyle {
    /// Where a choice shows its checkmark.
    enum CheckmarkPlacement {
        /// Before the name as its icon, keeping its space while hidden so names line up with other icon rows.
        case leading
        /// After the name, at the row's trailing edge.
        case trailing
    }

    @Environment(\.palette) private var palette
    private let isSelected: Bool
    private let placement: CheckmarkPlacement

    /// Marks whether the choice is the selected one.
    /// - Parameters:
    ///   - isSelected: Whether the choice is selected, which shows the checkmark.
    ///   - placement: Where the checkmark goes.
    fileprivate init(isSelected: Bool, placement: CheckmarkPlacement) {
        self.isSelected = isSelected
        self.placement = placement
    }

    /// Lays out the name and checkmark while delegating activation and feedback to a native button.
    /// - Parameter configuration: The original button's label, role, and action.
    /// - Returns: A native button that shows the name in the window's primary text color and reports its selection to
    ///   VoiceOver.
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            HStack {
                if placement == .leading {
                    // The checkmark is the label's icon, hidden but keeping its space when unselected, so every name
                    // starts where the text of a row with an icon does.
                    Label {
                        configuration.label
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(palette.accent)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                } else {
                    configuration.label
                }
                Spacer()
                if placement == .trailing, isSelected {
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
    /// A list choice that shows its name, with a checkmark while it's selected.
    /// - Parameters:
    ///   - isSelected: Whether the choice is selected.
    ///   - placement: Where the checkmark goes. The default is after the name.
    /// - Returns: The choice style.
    static func choice(isSelected: Bool, placement: ChoiceButtonStyle.CheckmarkPlacement = .trailing) -> Self {
        Self(isSelected: isSelected, placement: placement)
    }
}
